// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Ownable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Discount tiers
    struct DiscountTier {
        uint256 minPurchases;
        uint256 discountRate;
    }
    DiscountTier[] public discountTiers;

    // Mapping to track purchase counts per account
    mapping(bytes32 => uint256) public purchaseCounts;

    // Events
    event OracleUpdated(uint256 indexed newOracleId);
    event DiscountTierAdded(uint256 minPurchases, uint256 discountRate);
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
        
        // Initialize with default discount tiers
        discountTiers.push(DiscountTier(0, 0));  // 0% discount for 0-4 purchases
        discountTiers.push(DiscountTier(5, 500));  // 5% discount for 5-9 purchases
        discountTiers.push(DiscountTier(10, 1000));  // 10% discount for 10+ purchases
        
        // Set initial oracle ID
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
        require(value == bytes32(uint256(1)), "Oracle not active");
        
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
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 discountRate = 0;
        
        // Determine discount rate based on purchase count
        if (purchasedCounts >= 10) {
            discountRate = 1000; // 10% discount
        } else if (purchasedCounts >= 5) {
            discountRate = 500; // 5% discount
        }
        
        // Calculate discounted amount
        uint256 discountAmount = amount.mul(discountRate).div(10000);
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
    ) external onlyInitialized nonReentrant returns (bool result) {
        require(amount > 0, "Amount must be greater than 0");
        require(sendAccountId != bytes32(0) && fromAccountId != bytes32(0) && toAccountId != bytes32(0), "Invalid account IDs");
        
        // Validate accounts exist and are active
        require(_isAccountActive(sendAccountId), "Send account not active");
        require(_isAccountActive(fromAccountId), "From account not active");
        require(_isAccountActive(toAccountId), "To account not active");
        
        // Check balance
        require(_getAccountBalance(fromAccountId) >= amount, "Insufficient balance");
        
        // Apply discount
        uint256 discountedAmount = this.discount(amount, purchaseCounts[sendAccountId]);
        
        // Execute transfer
        bool transferResult = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(transferResult, "Transfer failed");
        
        // Update purchase count
        purchaseCounts[sendAccountId] = purchaseCounts[sendAccountId].add(1);
        
        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);
        
        return true;
    }

    // Internal functions

    function _isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return value == bytes32(uint256(1));
    }

    function _getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return uint256(value);
    }

    // Admin functions

    function addDiscountTier(uint256 minPurchases, uint256 discountRate) external onlyOwner {
        require(discountRate <= 10000, "Discount rate must be <= 100%");
        discountTiers.push(DiscountTier(minPurchases, discountRate));
        emit DiscountTierAdded(minPurchases, discountRate);
    }

    function removeDiscountTier(uint256 index) external onlyOwner {
        require(index < discountTiers.length, "Invalid index");
        discountTiers[index] = discountTiers[discountTiers.length - 1];
        discountTiers.pop();
        emit DiscountTierRemoved(index);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Helper functions

    function getDiscountTiersCount() external view returns (uint256) {
        return discountTiers.length;
    }

    function getDiscountTier(uint256 index) external view returns (uint256, uint256) {
        require(index < discountTiers.length, "Invalid index");
        return (discountTiers[index].minPurchases, discountTiers[index].discountRate);
    }

    function getPurchaseCount(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        return purchaseCounts[accountId];
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
            discountPercentage = 0;
        }

        // Apply additional discount based on purchase amount
        if (amount >= 1000 ether) {
            discountPercentage = discountPercentage.add(5);
        } else if (amount >= 500 ether) {
            discountPercentage = discountPercentage.add(3);
        } else if (amount >= 100 ether) {
            discountPercentage = discountPercentage.add(1);
        }

        // Ensure discount doesn't exceed maximum
        discountPercentage = discountPercentage > MAX_DISCOUNT ? MAX_DISCOUNT : discountPercentage;

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Applies discount to a purchase and executes the transfer
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if the discounted purchase was successful
     */
    function discountedPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 purchaseCount = purchaseCounts[sendAccountId];
        uint256 discountedAmount = discount(amount, purchaseCount);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(0),
            memo,
            traceId
        );

        if (transferResult) {
            purchaseCounts[sendAccountId] = purchaseCount.add(1);
            totalPurchaseAmounts[sendAccountId] = totalPurchaseAmounts[sendAccountId].add(discountedAmount);
            emit Discount(sendAccountId, item, amount, discountedAmount);
        }

        return transferResult;
    }

    /**
     * @dev Retrieves the purchase history for an account
     * @param accountId The account to query
     * @return count The number of purchases made
     * @return totalAmount The total amount spent after discounts
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 count, uint256 totalAmount) {
        require(accountId != bytes32(0), "Invalid accountId");
        return (purchaseCounts[accountId], totalPurchaseAmounts[accountId]);
    }

    /**
     * @dev Calculates the potential discount for a future purchase
     * @param accountId The account to calculate the discount for
     * @param amount The potential purchase amount
     * @return discountedAmount The amount after applying the potential discount
     */
    function calculatePotentialDiscount(bytes32 accountId, uint256 amount) external view returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(amount > 0, "Amount must be greater than zero");

        uint256 purchaseCount = purchaseCounts[accountId];
        return discount(amount, purchaseCount);
    }

    /**
     * @dev Applies a special one-time discount to an account
     * @param accountId The account to receive the special discount
     * @param discountPercentage The percentage of the special discount
     * @notice Only callable by admin
     */
    function applySpecialDiscount(bytes32 accountId, uint256 discountPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountPercentage > 0 && discountPercentage <= MAX_DISCOUNT, "Invalid discount percentage");

        // Implementation of special discount logic
        // This could involve storing a separate mapping for special discounts
        // or modifying the existing discount calculation logic
    }

    /**
     * @dev Resets the purchase count for an account
     * @param accountId The account to reset
     * @notice Only callable by admin
     */
    function resetPurchaseCount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = 0;
    }

    /**
     * @dev Adjusts the purchase count for an account
     * @param accountId The account to adjust
     * @param newCount The new purchase count
     * @notice Only callable by admin
     */
    function adjustPurchaseCount(bytes32 accountId, uint256 newCount) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = newCount;
    }

    /**
     * @dev Implements a loyalty program reward
     * @param accountId The account to reward
     * @param rewardAmount The amount of reward to add
     * @notice Only callable by admin
     */
    function applyLoyaltyReward(bytes32 accountId, uint256 rewardAmount) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(rewardAmount > 0, "Reward amount must be greater than zero");

        // Implementation of loyalty reward logic
        // This could involve creating a separate balance for rewards
        // or applying the reward as a discount on the next purchase
    }

    /**
     * @dev Retrieves the current discount tier for an account
     * @param accountId The account to query
     * @return tier The current discount tier (1, 2, 3, or 0 if no tier)
     */
    function getCurrentDiscountTier(bytes32 accountId) external view returns (uint256 tier) {
        require(accountId != bytes32(0), "Invalid accountId");

        uint256 purchaseCount = purchaseCounts[accountId];

        if (purchaseCount >= TIER3_THRESHOLD) {
            return 3;
        } else if (purchaseCount >= TIER2_THRESHOLD) {
            return 2;
        } else if (purchaseCount >= TIER1_THRESHOLD) {
            return 1;
        } else {
            return 0;
        }
    }

    /**
     * @dev Calculates the number of purchases needed to reach the next discount tier
     * @param accountId The account to calculate for
     * @return purchasesNeeded The number of additional purchases needed
     * @return nextTier The next discount tier (0 if already at max tier)
     */
    function purchasesToNextTier(bytes32 accountId) external view returns (uint256 purchasesNeeded, uint256 nextTier) {
        require(accountId != bytes32(0), "Invalid accountId");

        uint256 purchaseCount = purchaseCounts[accountId];

        if (purchaseCount >= TIER3_THRESHOLD) {
            return (0, 0); // Already at max tier
        } else if (purchaseCount >= TIER2_THRESHOLD) {
            return (TIER3_THRESHOLD.sub(purchaseCount), 3);
        } else if (purchaseCount >= TIER1_THRESHOLD) {
            return (TIER2_THRESHOLD.sub(purchaseCount), 2);
        } else {
            return (TIER1_THRESHOLD.sub(purchaseCount), 1);
        }
    }

    /**
     * @dev Applies a bulk discount to multiple items in a single transaction
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amounts Array of original purchase amounts for each item
     * @param items Array of identifiers for the items being purchased
     * @param memo Description of the bulk purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if the bulk discounted purchase was successful
     * @notice Arrays must be of equal length
     */
    function bulkDiscountedPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256[] memory amounts,
        bytes32[] memory items,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amounts.length == items.length, "Arrays must be of equal length");
        require(amounts.length > 0, "Must purchase at least one item");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 totalAmount = 0;
        uint256 totalDiscountedAmount = 0;
        uint256 purchaseCount = purchaseCounts[sendAccountId];

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than zero");
            totalAmount = totalAmount.add(amounts[i]);
            totalDiscountedAmount = totalDiscountedAmount.add(discount(amounts[i], purchaseCount));
        }

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            totalDiscountedAmount,
            bytes32(0),
            bytes32(0),
            memo,
            traceId
        );

        if (transferResult) {
            purchaseCounts[sendAccountId] = purchaseCount.add(1);
            totalPurchaseAmounts[sendAccountId] = totalPurchaseAmounts[sendAccountId].add(totalDiscountedAmount);

            for (uint256 i = 0; i < items.length; i++) {
                emit Discount(sendAccountId, items[i], amounts[i], discount(amounts[i], purchaseCount));
            }
        }

        return transferResult;
    }

    /**
     * @dev Applies a time-limited discount for a specific period
     * @param startTime The start time of the discount period
     * @param endTime The end time of the discount period
     * @param discountPercentage The percentage of the time-limited discount
     * @notice Only callable by admin
     */
    function setTimeLimitedDiscount(uint256 startTime, uint256 endTime, uint256 discountPercentage) external onlyAdmin {
        require(startTime < endTime, "Invalid time range");
        require(discountPercentage > 0 && discountPercentage <= MAX_DISCOUNT, "Invalid discount percentage");

        // Implementation of time-limited discount logic
        // This could involve storing the discount period and percentage
        // and modifying the discount calculation to check if the current time is within the discount period
    }

    /**
     * @dev Retrieves the current time-limited discount if active
     * @return active Whether a time-limited discount is currently active
     * @return discountPercentage The current time-limited discount percentage (0 if not active)
     */
    function getCurrentTimeLimitedDiscount() external view returns (bool active, uint256 discountPercentage) {
        // Implementation to check if there's an active time-limited discount
        // and return the current discount percentage if active
    }

    /**
     * @dev Applies a discount code to an account
     * @param accountId The account to apply the discount code to
     * @param discountCode The discount code to apply
     * @return success Whether the discount code was successfully applied
     */
    function applyDiscountCode(bytes32 accountId, bytes32 discountCode) external returns (bool success) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountCode != bytes32(0), "Invalid discount code");

        // Implementation of discount code logic
        // This could involve checking the validity of the discount code
        // and applying a special discount or reward to the account
    }

    /**
     * @dev Generates a unique discount code for an account
     * @param accountId The account to generate the discount code for
     * @return discountCode The generated discount code
     * @notice Only callable by admin
     */
    function generateDiscountCode(bytes32 accountId) external onlyAdmin returns (bytes32 discountCode) {
        require(accountId != bytes32(0), "Invalid accountId");

        // Implementation of discount code generation logic
        // This could involve creating a unique code based on the account and current time
        // and storing it for later validation
    }

    /**
     * @dev Applies a referral bonus to an account
     * @param referrerAccountId The account that made the referral
     * @param newAccountId The newly referred account
     * @notice Only callable by admin
     */
    function applyReferralBonus(bytes32 referrerAccountId, bytes32 newAccountId) external onlyAdmin {
        require(referrerAccountId != bytes32(0), "Invalid referrer accountId");
        require(newAccountId != bytes32(0), "Invalid new accountId");

        // Implementation of referral bonus logic
        // This could involve adding bonus points or applying a special discount
        // to both the referrer and the new account
    }

    /**
     * @dev Retrieves the referral statistics for an account
     * @param accountId The account to query
     * @return referralCount The number of successful referrals made by the account
     * @return totalBonus The total bonus earned from referrals
     */
    function getReferralStats(bytes32 accountId) external view returns (uint256 referralCount, uint256 totalBonus) {
        require(accountId != bytes32(0), "Invalid accountId");

        // Implementation to retrieve and return referral statistics
    }

    // Additional helper functions and internal logic...

Here's PART 3 of the smart contract implementation for the Discount contract:

// BEGIN PART 3

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;
        if (purchasedCounts == 0) {
            discountPercentage = 0; // No discount for first-time buyers
        } else if (purchasedCounts < 5) {
            discountPercentage = 5; // 5% discount for 1-4 purchases
        } else if (purchasedCounts < 10) {
            discountPercentage = 10; // 10% discount for 5-9 purchases
        } else if (purchasedCounts < 20) {
            discountPercentage = 15; // 15% discount for 10-19 purchases
        } else {
            discountPercentage = 20; // 20% discount for 20+ purchases
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to apply discount and execute transfer
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return bool True if the discounted transfer was successful
     */
    function _applyDiscountAndTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) internal returns (bool) {
        uint256 discountedAmount = discount(amount, purchasedCounts);
        
        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(purchasedCounts),
            memo,
            traceId
        );

        if (transferResult) {
            emit Discount(sendAccountId, item, amount, discountedAmount);
        }

        return transferResult;
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return bool True if the discounted purchase was successful
     */
    function purchaseWithDiscount(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 purchasedCounts = getPurchaseCount(sendAccountId);
        return _applyDiscountAndTransfer(sendAccountId, fromAccountId, toAccountId, amount, item, purchasedCounts, memo, traceId);
    }

    /**
     * @dev Retrieves the number of purchases made by an account
     * @param accountId The account to check
     * @return uint256 The number of purchases made
     */
    function getPurchaseCount(bytes32 accountId) public view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Increments the purchase count for an account
     * @param accountId The account to update
     */
    function incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Checks if an account is eligible for a loyalty bonus
     * @param accountId The account to check
     * @return bool True if the account is eligible for a loyalty bonus
     */
    function isEligibleForLoyaltyBonus(bytes32 accountId) public view returns (bool) {
        return purchaseCounts[accountId] > 0 && purchaseCounts[accountId] % 10 == 0;
    }

    /**
     * @dev Applies a loyalty bonus to an eligible account
     * @param accountId The account to receive the bonus
     * @return bool True if the bonus was successfully applied
     */
    function applyLoyaltyBonus(bytes32 accountId) external onlyAdmin returns (bool) {
        require(isEligibleForLoyaltyBonus(accountId), "Account not eligible for loyalty bonus");

        uint256 bonusAmount = 100 * (10 ** 18); // 100 tokens
        bool transferResult = customTransfer(
            bytes32(uint256(uint160(address(this)))),
            bytes32(uint256(uint160(address(this)))),
            accountId,
            bonusAmount,
            bytes32("LOYALTY_BONUS"),
            bytes32(0),
            "Loyalty bonus applied",
            keccak256(abi.encodePacked("LOYALTY_BONUS", accountId, block.timestamp))
        );

        if (transferResult) {
            emit LoyaltyBonusApplied(accountId, bonusAmount);
        }

        return transferResult;
    }

    /**
     * @dev Emitted when a loyalty bonus is applied to an account
     * @param accountId The account receiving the bonus
     * @param amount The amount of the loyalty bonus
     */
    event LoyaltyBonusApplied(bytes32 indexed accountId, uint256 amount);

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchaseCount The number of purchases made
     * @return uint256 The discount percentage (0-100)
     */
    function getDiscountRate(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount == 0) {
            return 0;
        } else if (purchaseCount < 5) {
            return 5;
        } else if (purchaseCount < 10) {
            return 10;
        } else if (purchaseCount < 20) {
            return 15;
        } else {
            return 20;
        }
    }

    /**
     * @dev Calculates the savings from a discount
     * @param originalAmount The original amount before discount
     * @param discountedAmount The amount after discount
     * @return uint256 The amount saved due to the discount
     */
    function calculateSavings(uint256 originalAmount, uint256 discountedAmount) public pure returns (uint256) {
        return originalAmount.sub(discountedAmount);
    }

    /**
     * @dev Checks if a special promotion is active
     * @return bool True if a special promotion is currently active
     */
    function isSpecialPromotionActive() public view returns (bool) {
        bytes32 promotionStatus = getOracleValue("SPECIAL_PROMOTION_ACTIVE");
        return promotionStatus == bytes32("ACTIVE");
    }

    /**
     * @dev Applies an additional discount if a special promotion is active
     * @param amount The current discounted amount
     * @return uint256 The final discounted amount after applying the promotion
     */
    function applySpecialPromotion(uint256 amount) public view returns (uint256) {
        if (isSpecialPromotionActive()) {
            uint256 promotionDiscount = amount.mul(5).div(100); // Additional 5% off
            return amount.sub(promotionDiscount);
        }
        return amount;
    }

    /**
     * @dev Executes a batch purchase with discounts applied
     * @param sendAccountIds Array of accounts initiating the purchases
     * @param fromAccountIds Array of source accounts for funds
     * @param toAccountIds Array of destination accounts (usually merchants)
     * @param amounts Array of original purchase amounts
     * @param items Array of identifiers for the items being purchased
     * @param memos Array of human readable transfer descriptions/reasons
     * @param traceIds Array of unique identifiers for tracking these transactions
     * @return bool[] Array of booleans indicating success of each discounted purchase
     */
    function batchPurchaseWithDiscount(
        bytes32[] memory sendAccountIds,
        bytes32[] memory fromAccountIds,
        bytes32[] memory toAccountIds,
        uint256[] memory amounts,
        bytes32[] memory items,
        string[] memory memos,
        bytes32[] memory traceIds
    ) external returns (bool[] memory) {
        require(
            sendAccountIds.length == fromAccountIds.length &&
            fromAccountIds.length == toAccountIds.length &&
            toAccountIds.length == amounts.length &&
            amounts.length == items.length &&
            items.length == memos.length &&
            memos.length == traceIds.length,
            "Array lengths must match"
        );

        bool[] memory results = new bool[](sendAccountIds.length);

        for (uint256 i = 0; i < sendAccountIds.length; i++) {
            results[i] = purchaseWithDiscount(
                sendAccountIds[i],
                fromAccountIds[i],
                toAccountIds[i],
                amounts[i],
                items[i],
                memos[i],
                traceIds[i]
            );
        }

        return results;
    }

    /**
     * @dev Retrieves purchase history for an account
     * @param accountId The account to check
     * @param startIndex The starting index of the history to retrieve
     * @param endIndex The ending index of the history to retrieve
     * @return PurchaseRecord[] Array of purchase records
     */
    function getPurchaseHistory(bytes32 accountId, uint256 startIndex, uint256 endIndex) 
        external 
        view 
        returns (PurchaseRecord[] memory) 
    {
        require(startIndex < endIndex, "Invalid index range");
        require(endIndex <= purchaseHistories[accountId].length, "End index out of bounds");

        uint256 length = endIndex - startIndex;
        PurchaseRecord[] memory history = new PurchaseRecord[](length);

        for (uint256 i = 0; i < length; i++) {
            history[i] = purchaseHistories[accountId][startIndex + i];
        }

        return history;
    }

    /**
     * @dev Internal function to add a purchase record to an account's history
     * @param accountId The account making the purchase
     * @param amount The purchase amount
     * @param discountedAmount The amount after discount
     * @param item The identifier of the purchased item
     */
    function _addPurchaseRecord(bytes32 accountId, uint256 amount, uint256 discountedAmount, bytes32 item) internal {
        PurchaseRecord memory record = PurchaseRecord({
            timestamp: block.timestamp,
            amount: amount,
            discountedAmount: discountedAmount,
            item: item
        });
        purchaseHistories[accountId].push(record);
    }

    /**
     * @dev Calculates the total spent by an account
     * @param accountId The account to calculate for
     * @return uint256 The total amount spent by the account
     */
    function calculateTotalSpent(bytes32 accountId) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < purchaseHistories[accountId].length; i++) {
            total = total.add(purchaseHistories[accountId][i].discountedAmount);
        }
        return total;
    }

    /**
     * @dev Determines if an account is a VIP based on total spent
     * @param accountId The account to check
     * @return bool True if the account is considered a VIP
     */
    function isVIP(bytes32 accountId) public view returns (bool) {
        uint256 totalSpent = calculateTotalSpent(accountId);
        return totalSpent >= VIP_THRESHOLD;
    }

    /**
     * @dev Applies an additional VIP discount if applicable
     * @param accountId The account making the purchase
     * @param amount The current discounted amount
     * @return uint256 The final discounted amount after applying VIP discount
     */
    function applyVIPDiscount(bytes32 accountId, uint256 amount) public view returns (uint256) {
        if (isVIP(accountId)) {
            uint256 vipDiscount = amount.mul(VIP_DISCOUNT_PERCENTAGE).div(100);
            return amount.sub(vipDiscount);
        }
        return amount;
    }

    /**
     * @dev Emitted when a VIP discount is applied
     * @param accountId The VIP account
     * @param originalAmount The amount before VIP discount
     * @param discountedAmount The amount after VIP discount
     */
    event VIPDiscountApplied(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount);

    /**
     * @dev Executes a purchase with all applicable discounts (regular, special promotion, VIP)
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return bool True if the discounted purchase was successful
     */
    function purchaseWithAllDiscounts(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 purchasedCounts = getPurchaseCount(sendAccountId);
        uint256 discountedAmount = discount(amount, purchasedCounts);
        discountedAmount = applySpecialPromotion(discountedAmount);
        discountedAmount = applyVIPDiscount(sendAccountId, discountedAmount);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(purchasedCounts),
            memo,
            traceId
        );

        if (transferResult) {
            emit Discount(sendAccountId, item, amount, discountedAmount);
            if (isVIP(sendAccountId)) {
                emit VIPDiscountApplied(sendAccountId, amount, discountedAmount);
            }
            _addPurchaseRecord(