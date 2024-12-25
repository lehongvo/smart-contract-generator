// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Ownable, ReentrancyGuard, Pausable, Initializable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;
    
    // Discount tiers
    struct DiscountTier {
        uint256 minPurchases;
        uint256 discountPercentage;
    }
    DiscountTier[] public discountTiers;

    // Events
    event OracleUpdated(uint256 indexed newOracleId);
    event DiscountTierAdded(uint256 minPurchases, uint256 discountPercentage);
    event DiscountTierRemoved(uint256 index);

    // Modifiers
    modifier onlyInitialized() {
        require(address(oracle) != address(0) && address(token) != address(0), "Contract not initialized");
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes discount contract with dependencies
     * @param _oracle Oracle contract for price/discount data
     * @param _token Token contract for payment handling
     * @notice Can only be called once during deployment
     * @notice Validates oracle and token addresses
     */
    function initialize(IOracle _oracle, ITransferable _token) external initializer {
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");
        
        oracle = _oracle;
        token = _token;
        
        // Initialize default discount tiers
        discountTiers.push(DiscountTier(0, 0));    // 0% discount for 0-4 purchases
        discountTiers.push(DiscountTier(5, 5));    // 5% discount for 5-9 purchases
        discountTiers.push(DiscountTier(10, 10));  // 10% discount for 10+ purchases
        
        // Set initial oracleId
        oracleId = 1;
        
        // Transfer ownership to msg.sender
        transferOwnership(msg.sender);
    }

    /**
     * @dev Returns contract version for upgrades
     * @return Version string in semver format
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Updates oracle instance used for discounts
     * @param _oracleId New oracle ID to use
     * @notice Only admin can update
     * @notice Validates oracle exists and is active
     */
    function setOracleId(uint256 _oracleId) external onlyOwner {
        require(_oracleId > 0, "Invalid oracle ID");
        
        // Validate oracle exists and is active
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        require(value == bytes32(uint256(1)), "Oracle is not active");
        
        oracleId = _oracleId;
        emit OracleUpdated(_oracleId);
    }

    /**
     * @dev Gets current oracle ID
     * @return Currently active oracle identifier
     */
    function getOracleId() external view returns (uint256) {
        return oracleId;
    }

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 discountPercentage = getDiscountPercentage(purchasedCounts);
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Executes a custom transfer between accounts
     * @param sendAccountId Account initiating the transfer (must be active)
     * @param fromAccountId Source account for funds (must have sufficient balance)
     * @param toAccountId Destination account (must be active)
     * @param amount Number of tokens to transfer (must be > 0)
     * @param miscValue1 First auxiliary parameter for transfer logic
     * @param miscValue2 Second auxiliary parameter for transfer logic
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if transfer completed successfully
     * @notice Validates all accounts exist and are active
     * @notice Checks sufficient balance in source account
     */
    function customTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2,
        string memory memo,
        bytes32 traceId
    ) external override onlyInitialized nonReentrant returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Calculate discount
        uint256 purchaseCount = purchaseCounts[sendAccountId];
        uint256 discountedAmount = this.discount(amount, purchaseCount);

        // Execute transfer
        bool transferResult = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(transferResult, "Transfer failed");

        // Update purchase count
        purchaseCounts[sendAccountId] = purchaseCount.add(1);

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    // Internal functions

    function getDiscountPercentage(uint256 purchaseCount) internal view returns (uint256) {
        for (uint256 i = discountTiers.length - 1; i >= 0; i--) {
            if (purchaseCount >= discountTiers[i].minPurchases) {
                return discountTiers[i].discountPercentage;
            }
        }
        return 0; // Default to no discount
    }

    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, accountId);
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return value == bytes32(uint256(1));
    }

    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return uint256(value);
    }

    // Admin functions

    function addDiscountTier(uint256 minPurchases, uint256 discountPercentage) external onlyOwner {
        require(discountPercentage <= 100, "Invalid discount percentage");
        discountTiers.push(DiscountTier(minPurchases, discountPercentage));
        emit DiscountTierAdded(minPurchases, discountPercentage);
    }

    function removeDiscountTier(uint256 index) external onlyOwner {
        require(index < discountTiers.length, "Invalid index");
        emit DiscountTierRemoved(index);
        discountTiers[index] = discountTiers[discountTiers.length - 1];
        discountTiers.pop();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Fallback and receive functions
    fallback() external payable {
        revert("Contract does not accept direct payments");
    }

    receive() external payable {
        revert("Contract does not accept direct payments");
    }
}

// END PART 1

Here's PART 2 of the smart contract implementation for the Discount contract:

// BEGIN PART 2

    using SafeMath for uint256;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;

    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount
    uint256 private constant MAX_DISCOUNT = 20; // 20% max discount

    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Mapping to store total purchase amounts for each account
    mapping(bytes32 => uint256) private totalPurchaseAmounts;

    // Mapping to store last purchase timestamp for each account
    mapping(bytes32 => uint256) private lastPurchaseTimestamp;

    // Cooldown period between purchases (in seconds)
    uint256 private constant PURCHASE_COOLDOWN = 1 hours;

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) public pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;

        if (purchasedCounts >= TIER3_THRESHOLD) {
            discountPercentage = TIER3_DISCOUNT;
        } else if (purchasedCounts >= TIER2_THRESHOLD) {
            discountPercentage = TIER2_DISCOUNT;
        } else if (purchasedCounts >= TIER1_THRESHOLD) {
            discountPercentage = TIER1_DISCOUNT;
        } else {
            return amount; // No discount for less than TIER1_THRESHOLD purchases
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Applies discount to a purchase and updates account history
     * @param accountId Account making the purchase
     * @param itemId Identifier of the item being purchased
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying discount
     */
    function applyDiscount(bytes32 accountId, bytes32 itemId, uint256 amount) internal returns (uint256) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(itemId != bytes32(0), "Invalid item ID");
        require(amount > 0, "Amount must be greater than zero");

        // Check purchase cooldown
        require(block.timestamp >= lastPurchaseTimestamp[accountId].add(PURCHASE_COOLDOWN), "Purchase cooldown period not elapsed");

        uint256 purchasedCounts = purchaseCounts[accountId];
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Update account purchase history
        purchaseCounts[accountId] = purchasedCounts.add(1);
        totalPurchaseAmounts[accountId] = totalPurchaseAmounts[accountId].add(amount);
        lastPurchaseTimestamp[accountId] = block.timestamp;

        // Emit discount event
        emit Discount(accountId, itemId, amount, discountedAmount);

        return discountedAmount;
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param sendAccountId Account making the purchase
     * @param itemId Identifier of the item being purchased
     * @param amount Original purchase amount
     * @return success True if the purchase was successful
     */
    function executePurchase(bytes32 sendAccountId, bytes32 itemId, uint256 amount) external returns (bool success) {
        uint256 discountedAmount = applyDiscount(sendAccountId, itemId, amount);

        // Execute the transfer using the token contract
        bool transferResult = token.customTransfer(
            sendAccountId,
            sendAccountId,
            bytes32(uint256(address(this))),
            discountedAmount,
            itemId,
            bytes32(0),
            "Discounted purchase",
            keccak256(abi.encodePacked(sendAccountId, itemId, block.timestamp))
        );

        require(transferResult, "Transfer failed");

        return true;
    }

    /**
     * @dev Retrieves the purchase history for an account
     * @param accountId Account to query
     * @return counts Number of purchases made
     * @return totalAmount Total amount spent on purchases
     * @return lastPurchase Timestamp of the last purchase
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 counts, uint256 totalAmount, uint256 lastPurchase) {
        require(accountId != bytes32(0), "Invalid account ID");

        return (
            purchaseCounts[accountId],
            totalPurchaseAmounts[accountId],
            lastPurchaseTimestamp[accountId]
        );
    }

    /**
     * @dev Calculates the current discount tier for an account
     * @param accountId Account to check
     * @return tier Current discount tier (0-3)
     * @return percentage Discount percentage for the current tier
     */
    function getCurrentDiscountTier(bytes32 accountId) external view returns (uint256 tier, uint256 percentage) {
        require(accountId != bytes32(0), "Invalid account ID");

        uint256 counts = purchaseCounts[accountId];

        if (counts >= TIER3_THRESHOLD) {
            return (3, TIER3_DISCOUNT);
        } else if (counts >= TIER2_THRESHOLD) {
            return (2, TIER2_DISCOUNT);
        } else if (counts >= TIER1_THRESHOLD) {
            return (1, TIER1_DISCOUNT);
        } else {
            return (0, 0);
        }
    }

    /**
     * @dev Checks if an account is eligible for a purchase (cooldown period elapsed)
     * @param accountId Account to check
     * @return eligible True if the account can make a purchase
     * @return remainingTime Time left in seconds before next eligible purchase
     */
    function isPurchaseEligible(bytes32 accountId) external view returns (bool eligible, uint256 remainingTime) {
        require(accountId != bytes32(0), "Invalid account ID");

        uint256 lastPurchase = lastPurchaseTimestamp[accountId];
        uint256 nextEligibleTimestamp = lastPurchase.add(PURCHASE_COOLDOWN);

        if (block.timestamp >= nextEligibleTimestamp) {
            return (true, 0);
        } else {
            return (false, nextEligibleTimestamp.sub(block.timestamp));
        }
    }

    /**
     * @dev Retrieves the oracle value for a specific key
     * @param key Data identifier to query
     * @return value Oracle value for the given key
     */
    function getOracleValue(bytes32 key) internal view returns (bytes32 value) {
        (bytes32 oracleValue, string memory err) = oracle.get(oracleId, key);
        require(bytes(err).length == 0, string(abi.encodePacked("Oracle error: ", err)));
        return oracleValue;
    }

    /**
     * @dev Updates discount tiers based on oracle data
     * @notice This function should be called periodically to adjust discount rates
     */
    function updateDiscountTiers() external onlyAdmin {
        bytes32 tier1ThresholdValue = getOracleValue("TIER1_THRESHOLD");
        bytes32 tier2ThresholdValue = getOracleValue("TIER2_THRESHOLD");
        bytes32 tier3ThresholdValue = getOracleValue("TIER3_THRESHOLD");

        bytes32 tier1DiscountValue = getOracleValue("TIER1_DISCOUNT");
        bytes32 tier2DiscountValue = getOracleValue("TIER2_DISCOUNT");
        bytes32 tier3DiscountValue = getOracleValue("TIER3_DISCOUNT");

        // Update threshold constants
        assembly {
            sstore(TIER1_THRESHOLD_SLOT, tier1ThresholdValue)
            sstore(TIER2_THRESHOLD_SLOT, tier2ThresholdValue)
            sstore(TIER3_THRESHOLD_SLOT, tier3ThresholdValue)
        }

        // Update discount percentages
        assembly {
            sstore(TIER1_DISCOUNT_SLOT, tier1DiscountValue)
            sstore(TIER2_DISCOUNT_SLOT, tier2DiscountValue)
            sstore(TIER3_DISCOUNT_SLOT, tier3DiscountValue)
        }

        emit DiscountTiersUpdated(
            uint256(tier1ThresholdValue),
            uint256(tier2ThresholdValue),
            uint256(tier3ThresholdValue),
            uint256(tier1DiscountValue),
            uint256(tier2DiscountValue),
            uint256(tier3DiscountValue)
        );
    }

    /**
     * @dev Emitted when discount tiers are updated
     * @param tier1Threshold New threshold for Tier 1
     * @param tier2Threshold New threshold for Tier 2
     * @param tier3Threshold New threshold for Tier 3
     * @param tier1Discount New discount percentage for Tier 1
     * @param tier2Discount New discount percentage for Tier 2
     * @param tier3Discount New discount percentage for Tier 3
     */
    event DiscountTiersUpdated(
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint256 tier1Discount,
        uint256 tier2Discount,
        uint256 tier3Discount
    );

    /**
     * @dev Applies a special one-time discount to an account
     * @param accountId Account to receive the special discount
     * @param discountPercentage Percentage of the special discount
     * @notice Only admin can apply special discounts
     */
    function applySpecialDiscount(bytes32 accountId, uint256 discountPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        require(discountPercentage > 0 && discountPercentage <= MAX_DISCOUNT, "Invalid discount percentage");

        SpecialDiscount storage specialDiscount = specialDiscounts[accountId];
        require(!specialDiscount.used, "Special discount already used");

        specialDiscount.percentage = discountPercentage;
        specialDiscount.expirationTime = block.timestamp.add(7 days);
        specialDiscount.used = false;

        emit SpecialDiscountApplied(accountId, discountPercentage);
    }

    /**
     * @dev Struct to store special discount information
     */
    struct SpecialDiscount {
        uint256 percentage;
        uint256 expirationTime;
        bool used;
    }

    // Mapping to store special discounts for accounts
    mapping(bytes32 => SpecialDiscount) private specialDiscounts;

    /**
     * @dev Emitted when a special discount is applied to an account
     * @param accountId Account receiving the special discount
     * @param discountPercentage Percentage of the special discount
     */
    event SpecialDiscountApplied(bytes32 accountId, uint256 discountPercentage);

    /**
     * @dev Checks if an account has an active special discount
     * @param accountId Account to check
     * @return active True if the account has an active special discount
     * @return percentage Percentage of the special discount
     */
    function hasActiveSpecialDiscount(bytes32 accountId) public view returns (bool active, uint256 percentage) {
        SpecialDiscount storage specialDiscount = specialDiscounts[accountId];
        if (!specialDiscount.used && block.timestamp <= specialDiscount.expirationTime) {
            return (true, specialDiscount.percentage);
        }
        return (false, 0);
    }

    /**
     * @dev Applies the special discount if available
     * @param accountId Account making the purchase
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying special discount
     */
    function applySpecialDiscount(bytes32 accountId, uint256 amount) internal returns (uint256 discountedAmount) {
        (bool hasDiscount, uint256 discountPercentage) = hasActiveSpecialDiscount(accountId);
        if (hasDiscount) {
            uint256 discountAmount = amount.mul(discountPercentage).div(100);
            discountedAmount = amount.sub(discountAmount);
            specialDiscounts[accountId].used = true;
            emit SpecialDiscountUsed(accountId, amount, discountedAmount);
        } else {
            discountedAmount = amount;
        }
    }

    /**
     * @dev Emitted when a special discount is used
     * @param accountId Account using the special discount
     * @param originalAmount Original purchase amount
     * @param discountedAmount Final amount after applying special discount
     */
    event SpecialDiscountUsed(bytes32 accountId, uint256 originalAmount, uint256 discountedAmount);

    /**
     * @dev Extends the expiration time of a special discount
     * @param accountId Account with the special discount
     * @param extensionDays Number of days to extend the expiration
     * @notice Only admin can extend special discounts
     */
    function extendSpecialDiscount(bytes32 accountId, uint256 extensionDays) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        require(extensionDays > 0, "Extension days must be greater than zero");

        SpecialDiscount storage specialDiscount = specialDiscounts[accountId];
        require(!specialDiscount.used, "Special discount already used");
        require(specialDiscount.expirationTime > block.timestamp, "Special discount already expired");

        specialDiscount.expirationTime = specialDiscount.expirationTime.add(extensionDays.mul(1 days));

        emit SpecialDiscountExtended(accountId, extensionDays);
    }

    /**
     * @dev Emitted when a special discount expiration is extended
     * @param accountId Account with the extended special discount
     * @param extensionDays Number of days the discount was extended
     */
    event SpecialDiscountExtended(bytes32 accountId, uint256 extensionDays);

    /**
     * @dev Cancels an active special discount for an account
     * @param accountId Account to cancel the special discount for
     * @notice Only admin can cancel special discounts
     */
    function cancelSpecialDiscount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");

        SpecialDiscount storage specialDiscount = specialDiscounts[accountId];
        require(!specialDiscount.used && specialDiscount.expirationTime > block.timestamp, "No active special discount to cancel");

        delete specialDiscounts[accountId];

        emit SpecialDiscountCancelled(accountId);
    }

    /**
     * @dev Emitted when a special discount is cancelled
     * @param accountId Account for which the special discount was cancelled
     */
    event SpecialDiscountCancelled(bytes32 accountId);

    /**
     * @dev Retrieves the loyalty points for an account
     * @param accountId Account to query
     * @return points Current loyalty points balance
     */
    function getLoyaltyPoints(bytes32 accountId) external view returns (uint256 points) {
        require(accountId != bytes32(0), "Invalid account ID");
        return loyaltyPoints[accountId];
    }

    // Mapping to store loyalty points for each account
    mapping(bytes32 => uint256) private

// BEGIN PART 3

    // Helper function to calculate tiered discount rate
    function _getTieredDiscountRate(uint256 purchasedCounts) internal pure returns (uint256) {
        if (purchasedCounts >= 100) {
            return 20; // 20% discount for 100+ purchases
        } else if (purchasedCounts >= 50) {
            return 15; // 15% discount for 50-99 purchases
        } else if (purchasedCounts >= 25) {
            return 10; // 10% discount for 25-49 purchases
        } else if (purchasedCounts >= 10) {
            return 5; // 5% discount for 10-24 purchases
        } else {
            return 0; // No discount for less than 10 purchases
        }
    }

    // Helper function to apply discount
    function _applyDiscount(uint256 amount, uint256 discountRate) internal pure returns (uint256) {
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    // Helper function to validate account
    function _validateAccount(bytes32 accountId) internal view {
        require(accountId != bytes32(0), "Invalid account ID");
        require(_accounts[accountId].isActive, "Account is not active");
    }

    // Helper function to check balance
    function _checkBalance(bytes32 accountId, uint256 amount) internal view {
        require(_accounts[accountId].balance >= amount, "Insufficient balance");
    }

    // Helper function to update balance
    function _updateBalance(bytes32 accountId, uint256 amount, bool isDebit) internal {
        if (isDebit) {
            _accounts[accountId].balance = _accounts[accountId].balance.sub(amount);
        } else {
            _accounts[accountId].balance = _accounts[accountId].balance.add(amount);
        }
    }

    // Helper function to validate and get oracle value
    function _getOracleValue(bytes32 key) internal view returns (bytes32) {
        (bytes32 value, string memory err) = oracle.get(oracleId, key);
        require(bytes(err).length == 0, string(abi.encodePacked("Oracle error: ", err)));
        return value;
    }

    // Implementation of discount function
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 discountRate = _getTieredDiscountRate(purchasedCounts);
        return _applyDiscount(amount, discountRate);
    }

    // Implementation of customTransfer function
    function customTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2,
        string memory memo,
        bytes32 traceId
    ) external override returns (bool result) {
        require(amount > 0, "Transfer amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        _validateAccount(sendAccountId);
        _validateAccount(fromAccountId);
        _validateAccount(toAccountId);

        _checkBalance(fromAccountId, amount);

        // Apply any discounts based on miscValue1 (assuming it represents purchasedCounts)
        uint256 discountedAmount = discount(amount, uint256(miscValue1));

        // Update balances
        _updateBalance(fromAccountId, discountedAmount, true);
        _updateBalance(toAccountId, discountedAmount, false);

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue2, amount, discountedAmount);

        return true;
    }

    // Additional helper functions for extensibility

    // Function to update account status
    function _updateAccountStatus(bytes32 accountId, bool isActive) internal {
        require(accountId != bytes32(0), "Invalid account ID");
        _accounts[accountId].isActive = isActive;
        emit AccountStatusUpdated(accountId, isActive);
    }

    // Event for account status updates
    event AccountStatusUpdated(bytes32 indexed accountId, bool isActive);

    // Function to add new discount tiers
    function _addDiscountTier(uint256 purchaseThreshold, uint256 discountRate) internal {
        require(purchaseThreshold > 0, "Purchase threshold must be greater than 0");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");
        _discountTiers[purchaseThreshold] = discountRate;
        emit DiscountTierAdded(purchaseThreshold, discountRate);
    }

    // Event for new discount tiers
    event DiscountTierAdded(uint256 purchaseThreshold, uint256 discountRate);

    // Mapping to store custom discount tiers
    mapping(uint256 => uint256) private _discountTiers;

    // Function to get custom discount rate
    function _getCustomDiscountRate(uint256 purchasedCounts) internal view returns (uint256) {
        uint256 highestThreshold = 0;
        uint256 discountRate = 0;

        for (uint256 i = 0; i < _discountTierThresholds.length; i++) {
            uint256 threshold = _discountTierThresholds[i];
            if (purchasedCounts >= threshold && threshold > highestThreshold) {
                highestThreshold = threshold;
                discountRate = _discountTiers[threshold];
            }
        }

        return discountRate;
    }

    // Array to store discount tier thresholds for iteration
    uint256[] private _discountTierThresholds;

    // Function to add a new discount tier
    function addDiscountTier(uint256 purchaseThreshold, uint256 discountRate) external onlyAdmin {
        _addDiscountTier(purchaseThreshold, discountRate);
        _discountTierThresholds.push(purchaseThreshold);
    }

    // Function to remove a discount tier
    function removeDiscountTier(uint256 purchaseThreshold) external onlyAdmin {
        require(_discountTiers[purchaseThreshold] != 0, "Discount tier does not exist");
        delete _discountTiers[purchaseThreshold];

        // Remove threshold from array
        for (uint256 i = 0; i < _discountTierThresholds.length; i++) {
            if (_discountTierThresholds[i] == purchaseThreshold) {
                _discountTierThresholds[i] = _discountTierThresholds[_discountTierThresholds.length - 1];
                _discountTierThresholds.pop();
                break;
            }
        }

        emit DiscountTierRemoved(purchaseThreshold);
    }

    // Event for removed discount tiers
    event DiscountTierRemoved(uint256 purchaseThreshold);

    // Function to update an existing discount tier
    function updateDiscountTier(uint256 purchaseThreshold, uint256 newDiscountRate) external onlyAdmin {
        require(_discountTiers[purchaseThreshold] != 0, "Discount tier does not exist");
        require(newDiscountRate <= 100, "Discount rate cannot exceed 100%");
        _discountTiers[purchaseThreshold] = newDiscountRate;
        emit DiscountTierUpdated(purchaseThreshold, newDiscountRate);
    }

    // Event for updated discount tiers
    event DiscountTierUpdated(uint256 purchaseThreshold, uint256 newDiscountRate);

    // Function to get all discount tiers
    function getDiscountTiers() external view returns (uint256[] memory thresholds, uint256[] memory rates) {
        thresholds = _discountTierThresholds;
        rates = new uint256[](thresholds.length);
        for (uint256 i = 0; i < thresholds.length; i++) {
            rates[i] = _discountTiers[thresholds[i]];
        }
    }

    // Function to calculate weighted average discount
    function calculateWeightedDiscount(uint256[] memory amounts, uint256[] memory purchaseCounts) external view returns (uint256) {
        require(amounts.length == purchaseCounts.length, "Arrays must have equal length");
        require(amounts.length > 0, "Arrays cannot be empty");

        uint256 totalAmount = 0;
        uint256 totalDiscount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 discountRate = _getCustomDiscountRate(purchaseCounts[i]);
            uint256 discountedAmount = _applyDiscount(amounts[i], discountRate);
            totalAmount = totalAmount.add(amounts[i]);
            totalDiscount = totalDiscount.add(amounts[i].sub(discountedAmount));
        }

        return totalDiscount.mul(100).div(totalAmount);
    }

    // Function to apply bulk discounts
    function applyBulkDiscounts(uint256[] memory amounts, uint256[] memory purchaseCounts) external view returns (uint256[] memory discountedAmounts) {
        require(amounts.length == purchaseCounts.length, "Arrays must have equal length");
        discountedAmounts = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 discountRate = _getCustomDiscountRate(purchaseCounts[i]);
            discountedAmounts[i] = _applyDiscount(amounts[i], discountRate);
        }
    }

    // Function to estimate savings for future purchases
    function estimateFutureSavings(uint256 currentPurchaseCount, uint256[] memory futurePurchaseAmounts) external view returns (uint256[] memory estimatedSavings) {
        estimatedSavings = new uint256[](futurePurchaseAmounts.length);

        for (uint256 i = 0; i < futurePurchaseAmounts.length; i++) {
            uint256 futureDiscountRate = _getCustomDiscountRate(currentPurchaseCount + i + 1);
            uint256 discountedAmount = _applyDiscount(futurePurchaseAmounts[i], futureDiscountRate);
            estimatedSavings[i] = futurePurchaseAmounts[i].sub(discountedAmount);
        }
    }

    // Function to calculate loyalty points based on purchases
    function calculateLoyaltyPoints(uint256 purchaseAmount, uint256 purchaseCount) external pure returns (uint256) {
        uint256 basePoints = purchaseAmount.div(100); // 1 point per 100 units spent
        uint256 bonusMultiplier = (purchaseCount / 10).add(1); // Bonus multiplier increases every 10 purchases
        return basePoints.mul(bonusMultiplier);
    }

    // Struct to store promotion details
    struct Promotion {
        bytes32 promoCode;
        uint256 discountRate;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    // Mapping to store promotions
    mapping(bytes32 => Promotion) private _promotions;

    // Function to add a new promotion
    function addPromotion(bytes32 promoCode, uint256 discountRate, uint256 startTime, uint256 endTime) external onlyAdmin {
        require(promoCode != bytes32(0), "Invalid promo code");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");
        require(startTime < endTime, "Invalid time range");
        require(!_promotions[promoCode].isActive, "Promotion already exists");

        _promotions[promoCode] = Promotion({
            promoCode: promoCode,
            discountRate: discountRate,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit PromotionAdded(promoCode, discountRate, startTime, endTime);
    }

    // Event for added promotions
    event PromotionAdded(bytes32 promoCode, uint256 discountRate, uint256 startTime, uint256 endTime);

    // Function to apply promotional discount
    function applyPromotionalDiscount(uint256 amount, bytes32 promoCode) external view returns (uint256) {
        require(_promotions[promoCode].isActive, "Promotion not found or inactive");
        require(block.timestamp >= _promotions[promoCode].startTime && block.timestamp <= _promotions[promoCode].endTime, "Promotion not active");

        return _applyDiscount(amount, _promotions[promoCode].discountRate);
    }

    // Function to deactivate a promotion
    function deactivatePromotion(bytes32 promoCode) external onlyAdmin {
        require(_promotions[promoCode].isActive, "Promotion not found or already inactive");
        _promotions[promoCode].isActive = false;
        emit PromotionDeactivated(promoCode);
    }

    // Event for deactivated promotions
    event PromotionDeactivated(bytes32 promoCode);

    // Function to get promotion details
    function getPromotionDetails(bytes32 promoCode) external view returns (Promotion memory) {
        require(_promotions[promoCode].isActive, "Promotion not found or inactive");
        return _promotions[promoCode];
    }

    // Struct to store referral program details
    struct ReferralProgram {
        uint256 referrerBonus;
        uint256 refereeDiscount;
        bool isActive;
    }

    // Current referral program
    ReferralProgram private _currentReferralProgram;

    // Mapping to track referrals
    mapping(bytes32 => bytes32) private _referrals; // refereeAccountId => referrerAccountId

    // Function to set up referral program
    function setupReferralProgram(uint256 referrerBonus, uint256 refereeDiscount) external onlyAdmin {
        require(referrerBonus <= 100, "Referrer bonus cannot exceed 100%");
        require(refereeDiscount <= 100, "Referee discount cannot exceed 100%");

        _currentReferralProgram = ReferralProgram({
            referrerBonus: referrerBonus,
            refereeDiscount: refereeDiscount,
            isActive: true
        });

        emit ReferralProgramUpdated(referrerBonus, refereeDiscount);
    }

    // Event for updated referral program
    event ReferralProgramUpdated(uint256 referrerBonus, uint256 refereeDiscount);

    // Function to register a referral
    function registerReferral(bytes32 refereeAccountId, bytes32 referrerAccountId) external {
        require(_currentReferralProgram.isActive, "Referral program is not active");
        require(refereeAccountId != bytes32(0) && referrerAccountId != bytes32(0), "Invalid account IDs");
        require(_referrals[refereeAccountId] == bytes32(0), "Referee already has a referrer");
        require(refereeAccountId != referrerAccountId, "Cannot refer yourself");

        _referrals[refereeAccountId] = referrerAccountId;
        emit ReferralRegistered(refereeAccountId, referrerAccountId);
    }

    // Event for registered referrals
    event ReferralRegistered(bytes32 refereeAccountId, bytes32 referrerAccountId);

    // Function to apply referral discount
    function applyReferralDiscount(uint256 amount, bytes32 accountId) external view returns (uint256) {
        require(_currentReferralProgram.isActive, "Referral program is not active");
        require(_referrals[accountId] != bytes32(0), "No referral found for this account");

        return _applyDiscount(amount, _currentReferralProgram.referee