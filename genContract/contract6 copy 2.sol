// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Ownable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount

    // Events
    event OracleUpdated(uint256 indexed oldOracleId, uint256 indexed newOracleId);
    event DiscountApplied(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, uint256 discountPercentage);

    // Modifiers
    modifier onlyInitialized() {
        require(address(oracle) != address(0) && address(token) != address(0), "Discount: Not initialized");
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Discount: Invalid account ID");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Discount: Amount must be greater than zero");
        _;
    }

    /**
     * @dev Constructor is empty as contract uses initializer pattern
     */
    constructor() {
        // Intentionally left empty
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
     * @dev Modifier to ensure only admin can call a function
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not the admin");
        _;
    }

    /**
     * @dev Modifier to check if the contract is initialized
     */
    modifier whenInitialized() {
        require(isInitialized, "Contract is not initialized");
        _;
    }

    /**
     * @dev Initializes discount contract with dependencies
     * @param _oracle Oracle contract for price/discount data
     * @param _token Token contract for payment handling
     */
    function initialize(IOracle _oracle, ITransferable _token) external override {
        require(!isInitialized, "Contract is already initialized");
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");

        oracle = _oracle;
        token = _token;
        admin = msg.sender;
        isInitialized = true;

        emit ContractInitialized(address(_oracle), address(_token));
    }

    /**
     * @dev Returns contract version for upgrades
     * @return Version string in semver format
     */
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Updates oracle instance used for discounts
     * @param _oracleId New oracle ID to use
     */
    function setOracleId(uint256 _oracleId) external override onlyAdmin whenInitialized {
        require(_oracleId > 0, "Invalid oracle ID");
        
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        require(value == bytes32(uint256(1)), "Oracle is not active");

        oracleId = _oracleId;
        emit OracleIdUpdated(_oracleId);
    }

    /**
     * @dev Gets current oracle ID
     * @return Currently active oracle identifier
     */
    function getOracleId() external view override whenInitialized returns (uint256) {
        return oracleId;
    }

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");

        uint256 discountPercentage;

        if (purchasedCounts >= TIER3_THRESHOLD) {
            discountPercentage = TIER3_DISCOUNT;
        } else if (purchasedCounts >= TIER2_THRESHOLD) {
            discountPercentage = TIER2_DISCOUNT;
        } else if (purchasedCounts >= TIER1_THRESHOLD) {
            discountPercentage = TIER1_DISCOUNT;
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        uint256 finalAmount = amount.sub(discountAmount);

        return finalAmount;
    }

    /**
     * @dev Executes a custom transfer between accounts with discount applied
     * @param sendAccountId Account initiating the transfer (must be active)
     * @param fromAccountId Source account for funds (must have sufficient balance)
     * @param toAccountId Destination account (must be active)
     * @param amount Number of tokens to transfer (must be > 0)
     * @param miscValue1 First auxiliary parameter for transfer logic
     * @param miscValue2 Second auxiliary parameter for transfer logic
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if transfer completed successfully
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
    ) external override whenInitialized returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Check purchase cooldown
        require(block.timestamp.sub(lastPurchaseTimestamp[sendAccountId]) >= PURCHASE_COOLDOWN, "Purchase cooldown not met");

        // Update purchase count and total amount
        purchaseCounts[sendAccountId] = purchaseCounts[sendAccountId].add(1);
        totalPurchaseAmounts[sendAccountId] = totalPurchaseAmounts[sendAccountId].add(amount);

        // Calculate discounted amount
        uint256 discountedAmount = discount(amount, purchaseCounts[sendAccountId]);

        // Execute transfer with discounted amount
        result = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(result, "Transfer failed");

        // Update last purchase timestamp
        lastPurchaseTimestamp[sendAccountId] = block.timestamp;

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return result;
    }

    /**
     * @dev Retrieves purchase history for an account
     * @param accountId Account to query
     * @return count Number of purchases made
     * @return totalAmount Total amount spent (before discounts)
     * @return lastPurchase Timestamp of last purchase
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 count, uint256 totalAmount, uint256 lastPurchase) {
        require(accountId != bytes32(0), "Invalid accountId");

        count = purchaseCounts[accountId];
        totalAmount = totalPurchaseAmounts[accountId];
        lastPurchase = lastPurchaseTimestamp[accountId];
    }

    /**
     * @dev Applies a special one-time discount to an account
     * @param accountId Account to receive the special discount
     * @param discountPercentage Percentage of discount to apply (0-100)
     */
    function applySpecialDiscount(bytes32 accountId, uint256 discountPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountPercentage > 0 && discountPercentage <= MAX_DISCOUNT, "Invalid discount percentage");

        specialDiscounts[accountId] = discountPercentage;
        emit SpecialDiscountApplied(accountId, discountPercentage);
    }

    /**
     * @dev Removes a special discount from an account
     * @param accountId Account to remove the special discount from
     */
    function removeSpecialDiscount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(specialDiscounts[accountId] > 0, "No special discount found");

        delete specialDiscounts[accountId];
        emit SpecialDiscountRemoved(accountId);
    }

    /**
     * @dev Sets a new purchase cooldown period
     * @param newCooldown New cooldown period in seconds
     */
    function setPurchaseCooldown(uint256 newCooldown) external onlyAdmin {
        require(newCooldown > 0, "Cooldown must be greater than 0");
        uint256 oldCooldown = PURCHASE_COOLDOWN;
        PURCHASE_COOLDOWN = newCooldown;
        emit PurchaseCooldownUpdated(oldCooldown, newCooldown);
    }

    /**
     * @dev Upgrades the contract to a new implementation
     * @param newImplementation Address of the new implementation contract
     */
    function upgradeContract(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "Invalid implementation address");
        require(newImplementation != address(this), "Cannot upgrade to same implementation");

        // Perform upgrade logic here (e.g., using a proxy pattern)
        // This is a simplified example and should be expanded based on your upgrade strategy
        
        emit ContractUpgraded(address(this), newImplementation);
    }

    /**
     * @dev Pauses all discount operations
     */
    function pauseDiscounts() external onlyAdmin {
        require(!paused, "Discounts are already paused");
        paused = true;
        emit DiscountsPaused();
    }

    /**
     * @dev Resumes all discount operations
     */
    function resumeDiscounts() external onlyAdmin {
        require(paused, "Discounts are not paused");
        paused = false;
        emit DiscountsResumed();
    }

    /**
     * @dev Internal function to validate account status
     * @param accountId Account to validate
     */
    function _validateAccount(bytes32 accountId) internal view {
        require(accountId != bytes32(0), "Invalid account ID");
        
        (bytes32 value, string memory err) = oracle.get(oracleId, accountId);
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Account lookup failed");
        require(value == bytes32(uint256(1)), "Account is not active");
    }

    /**
     * @dev Internal function to apply loyalty bonuses
     * @param accountId Account to apply bonus to
     * @param amount Purchase amount
     * @return bonusAmount Amount of bonus applied
     */
    function _applyLoyaltyBonus(bytes32 accountId, uint256 amount) internal returns (uint256 bonusAmount) {
        uint256 totalPurchases = totalPurchaseAmounts[accountId];
        
        if (totalPurchases >= TIER3_THRESHOLD.mul(1000 ether)) {
            bonusAmount = amount.mul(5).div(100); // 5% bonus
        } else if (totalPurchases >= TIER2_THRESHOLD.mul(1000 ether)) {
            bonusAmount = amount.mul(3).div(100); // 3% bonus
        } else if (totalPurchases >= TIER1_THRESHOLD.mul(1000 ether)) {
            bonusAmount = amount.mul(1).div(100); // 1% bonus
        }

        if (bonusAmount > 0) {
            // Apply bonus logic here (e.g., mint bonus tokens or add to balance)
            emit LoyaltyBonusApplied(accountId, bonusAmount);
        }

        return bonusAmount;
    }

    // Additional events
    event ContractInitialized(address indexed oracle, address indexed token);
    event OracleIdUpdated(uint256 newOracleId);
    event SpecialDiscountApplied(bytes32 indexed accountId, uint256 discountPercentage);
    event SpecialDiscountRemoved(bytes32 indexed accountId);
    event PurchaseCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event ContractUpgraded(address indexed oldImplementation, address indexed newImplementation);
    event DiscountsPaused();
    event DiscountsResumed();
    event LoyaltyBonusApplied(bytes32 indexed accountId, uint256 bonusAmount);

// END PART 2

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

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 discountRate = _getTieredDiscountRate(purchasedCounts);
        return _applyDiscount(amount, discountRate);
    }

    // Additional helper function for complex discount calculations
    function _calculateComplexDiscount(uint256 amount, uint256 purchasedCounts, bytes32 itemCategory) internal view returns (uint256) {
        uint256 baseDiscount = _getTieredDiscountRate(purchasedCounts);
        
        // Get category-specific discount from oracle
        (bytes32 categoryDiscountRaw,) = oracle.get(oracleId, itemCategory);
        uint256 categoryDiscount = uint256(categoryDiscountRaw);
        
        // Combine discounts (assuming they stack)
        uint256 totalDiscountRate = baseDiscount.add(categoryDiscount);
        
        // Cap total discount at 30%
        if (totalDiscountRate > 30) {
            totalDiscountRate = 30;
        }
        
        return _applyDiscount(amount, totalDiscountRate);
    }

    // Event for logging complex discounts
    event ComplexDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, uint256 purchasedCounts, bytes32 itemCategory);

    /**
     * @dev Applies a complex discount calculation
     * @param accountId The account receiving the discount
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @param itemCategory Category of the item being purchased
     * @return discountedAmount The final discounted amount
     */
    function applyComplexDiscount(bytes32 accountId, uint256 amount, uint256 purchasedCounts, bytes32 itemCategory) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(itemCategory != bytes32(0), "Invalid item category");

        discountedAmount = _calculateComplexDiscount(amount, purchasedCounts, itemCategory);
        
        emit ComplexDiscount(accountId, amount, discountedAmount, purchasedCounts, itemCategory);
        return discountedAmount;
    }

    // Bulk discount application function
    function applyBulkDiscount(bytes32[] memory accountIds, uint256[] memory amounts, uint256[] memory purchasedCounts) external returns (uint256[] memory discountedAmounts) {
        require(accountIds.length == amounts.length && amounts.length == purchasedCounts.length, "Array lengths must match");
        
        discountedAmounts = new uint256[](amounts.length);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            require(accountIds[i] != bytes32(0), "Invalid account ID");
            require(amounts[i] > 0, "Amount must be greater than 0");
            
            discountedAmounts[i] = discount(amounts[i], purchasedCounts[i]);
            
            emit Discount(accountIds[i], bytes32("BULK_ITEM"), amounts[i], discountedAmounts[i]);
        }
        
        return discountedAmounts;
    }

    // Function to update discount tiers
    function updateDiscountTiers(uint256[] memory thresholds, uint256[] memory rates) external onlyAdmin {
        require(thresholds.length == rates.length, "Thresholds and rates must have the same length");
        require(thresholds.length > 0, "Must provide at least one tier");
        
        for (uint256 i = 0; i < thresholds.length; i++) {
            require(rates[i] <= 100, "Discount rate cannot exceed 100%");
            if (i > 0) {
                require(thresholds[i] > thresholds[i-1], "Thresholds must be in ascending order");
            }
        }
        
        // Update the contract's discount tiers (assuming we have storage for this)
        // This is a simplified example; actual implementation would depend on how tiers are stored
        for (uint256 i = 0; i < thresholds.length; i++) {
            discountTiers[i] = DiscountTier(thresholds[i], rates[i]);
        }
        
        emit DiscountTiersUpdated(thresholds, rates);
    }

    // Event for updating discount tiers
    event DiscountTiersUpdated(uint256[] thresholds, uint256[] rates);

    // Structure to hold discount tier information
    struct DiscountTier {
        uint256 threshold;
        uint256 rate;
    }

    // Mapping to store discount tiers
    mapping(uint256 => DiscountTier) public discountTiers;

    // Function to get current discount tiers
    function getDiscountTiers() external view returns (uint256[] memory thresholds, uint256[] memory rates) {
        uint256 tierCount = 0;
        for (uint256 i = 0; i < 100; i++) { // Assuming a max of 100 tiers
            if (discountTiers[i].threshold == 0 && i > 0) break;
            tierCount++;
        }
        
        thresholds = new uint256[](tierCount);
        rates = new uint256[](tierCount);
        
        for (uint256 i = 0; i < tierCount; i++) {
            thresholds[i] = discountTiers[i].threshold;
            rates[i] = discountTiers[i].rate;
        }
        
        return (thresholds, rates);
    }

    // Function to apply time-limited discounts
    function applyTimeLimitedDiscount(bytes32 accountId, uint256 amount, uint256 purchasedCounts, uint256 expirationTime) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(expirationTime > block.timestamp, "Discount has expired");
        
        uint256 baseDiscountedAmount = discount(amount, purchasedCounts);
        
        // Apply an additional 5% discount for time-limited offers
        discountedAmount = baseDiscountedAmount.mul(95).div(100);
        
        emit TimeLimitedDiscount(accountId, amount, discountedAmount, expirationTime);
        return discountedAmount;
    }

    // Event for time-limited discounts
    event TimeLimitedDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, uint256 expirationTime);

    // Function to check if an account is eligible for a special discount
    function isEligibleForSpecialDiscount(bytes32 accountId) public view returns (bool) {
        // This could check various conditions like account age, total spend, etc.
        // For this example, we'll use a simple check based on purchased counts
        uint256 purchasedCounts = getPurchaseCountForAccount(accountId);
        return purchasedCounts >= 100;
    }

    // Helper function to get purchase count for an account (placeholder implementation)
    function getPurchaseCountForAccount(bytes32 accountId) internal view returns (uint256) {
        // In a real implementation, this would query some storage or external service
        // For this example, we'll return a dummy value
        return uint256(uint160(bytes20(accountId))) % 200; // Returns a number between 0 and 199
    }

    // Function to apply a special discount for eligible accounts
    function applySpecialDiscount(bytes32 accountId, uint256 amount) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(isEligibleForSpecialDiscount(accountId), "Account not eligible for special discount");
        
        // Apply a flat 25% discount for special eligible accounts
        discountedAmount = amount.mul(75).div(100);
        
        emit SpecialDiscount(accountId, amount, discountedAmount);
        return discountedAmount;
    }

    // Event for special discounts
    event SpecialDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount);

    // Function to calculate loyalty points based on purchase amount
    function calculateLoyaltyPoints(uint256 purchaseAmount) public pure returns (uint256) {
        // For example, 1 point per 10 units of currency spent
        return purchaseAmount.div(10);
    }

    // Function to apply discount based on loyalty points
    function applyLoyaltyDiscount(bytes32 accountId, uint256 amount, uint256 loyaltyPoints) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        
        // Calculate discount percentage based on loyalty points
        // For example, 1% discount per 100 loyalty points, up to a maximum of 10%
        uint256 discountPercentage = loyaltyPoints.div(100);
        if (discountPercentage > 10) {
            discountPercentage = 10;
        }
        
        discountedAmount = amount.mul(100 - discountPercentage).div(100);
        
        emit LoyaltyDiscount(accountId, amount, discountedAmount, loyaltyPoints);
        return discountedAmount;
    }

    // Event for loyalty-based discounts
    event LoyaltyDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, uint256 loyaltyPoints);

    // Function to apply a referral discount
    function applyReferralDiscount(bytes32 accountId, bytes32 referrerId, uint256 amount) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0) && referrerId != bytes32(0), "Invalid account or referrer ID");
        require(amount > 0, "Amount must be greater than 0");
        require(accountId != referrerId, "An account cannot refer itself");
        
        // Apply a 10% discount for referred purchases
        discountedAmount = amount.mul(90).div(100);
        
        emit ReferralDiscount(accountId, referrerId, amount, discountedAmount);
        return discountedAmount;
    }

    // Event for referral discounts
    event ReferralDiscount(bytes32 indexed accountId, bytes32 indexed referrerId, uint256 originalAmount, uint256 discountedAmount);

    // Function to apply a bundle discount
    function applyBundleDiscount(bytes32 accountId, uint256[] memory itemAmounts) external returns (uint256 totalDiscountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(itemAmounts.length > 1, "Bundle must include at least two items");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < itemAmounts.length; i++) {
            require(itemAmounts[i] > 0, "Item amount must be greater than 0");
            totalAmount = totalAmount.add(itemAmounts[i]);
        }
        
        // Apply a 15% discount for bundles
        totalDiscountedAmount = totalAmount.mul(85).div(100);
        
        emit BundleDiscount(accountId, totalAmount, totalDiscountedAmount, itemAmounts.length);
        return totalDiscountedAmount;
    }

    // Event for bundle discounts
    event BundleDiscount(bytes32 indexed accountId, uint256 originalTotalAmount, uint256 discountedTotalAmount, uint256 itemCount);

    // Function to apply a seasonal discount
    function applySeasonalDiscount(bytes32 accountId, uint256 amount, bytes32 seasonCode) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        
        // Get the seasonal discount rate from the oracle
        (bytes32 seasonalDiscountRateRaw,) = oracle.get(oracleId, seasonCode);
        uint256 seasonalDiscountRate = uint256(seasonalDiscountRateRaw);
        
        require(seasonalDiscountRate > 0, "No active seasonal discount");
        require(seasonalDiscountRate <= 50, "Invalid seasonal discount rate");
        
        discountedAmount = amount.mul(100 - seasonalDiscountRate).div(100);
        
        emit SeasonalDiscount(accountId, amount, discountedAmount, seasonCode, seasonalDiscountRate);
        return discountedAmount;
    }

    // Event for seasonal discounts
    event SeasonalDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, bytes32 seasonCode, uint256 discountRate);

    // Function to apply a first-time purchase discount
    function applyFirstTimePurchaseDiscount(bytes32 accountId, uint256 amount) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        
        // Check if this is the first purchase for the account
        require(!hasAccountMadePurchase[accountId], "Not eligible for first-time purchase discount");
        
        // Apply a 20% discount for first-time purchases
        discountedAmount = amount.mul(80).div(100);
        
        // Mark the account as having made a purchase
        hasAccountMadePurchase[accountId] = true;
        
        emit FirstTimePurchaseDiscount(accountId, amount, discountedAmount);
        return discountedAmount;
    }

    // Mapping to track if an account has made a purchase
    mapping(bytes32 => bool) private hasAccountMadePurchase;

    // Event for first-time purchase discounts
    event FirstTimePurchaseDiscount(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount);

    // Function to apply a volume-based discount
    function applyVolumeDiscount(bytes32 accountId, uint256 amount, uint256 quantity) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(quantity > 0, "Quantity must be greater than 0");
        
        uint256 discountRate;