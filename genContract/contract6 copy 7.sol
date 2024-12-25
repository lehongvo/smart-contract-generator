// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Initializable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to track purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;
    
    // Discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount
    uint256 private constant MAX_DISCOUNT = 20; // 20% max discount

    // Events
    event OracleUpdated(uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 accountId, uint256 newCount);

    // Modifiers
    modifier onlyActiveOracle() {
        require(oracle.get(oracleId, "ACTIVE") == bytes32(uint256(1)), "Oracle is not active");
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
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
        oracleId = 1; // Default oracle ID
        
        // Initialize Ownable
        __Ownable_init();
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
        (bytes32 isActive, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(isActive == bytes32(uint256(1)), "Oracle is not active");
        require(bytes(err).length == 0, "Oracle error");
        
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
        
        uint256 discountPercentage;
        
        if (purchasedCounts >= TIER3_THRESHOLD) {
            discountPercentage = TIER3_DISCOUNT;
        } else if (purchasedCounts >= TIER2_THRESHOLD) {
            discountPercentage = TIER2_DISCOUNT;
        } else if (purchasedCounts >= TIER1_THRESHOLD) {
            discountPercentage = TIER1_DISCOUNT;
        } else {
            return amount; // No discount
        }
        
        // Apply discount
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        
        // Ensure discount doesn't exceed maximum
        uint256 maxDiscountAmount = amount.mul(MAX_DISCOUNT).div(100);
        discountAmount = discountAmount > maxDiscountAmount ? maxDiscountAmount : discountAmount;
        
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
    ) external override onlyActiveOracle nonReentrant returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Check if accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Apply discount based on purchase history
        uint256 discountedAmount = this.discount(amount, purchaseCounts[sendAccountId]);

        // Perform transfer
        bool transferSuccess = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(transferSuccess, "Transfer failed");

        // Increment purchase count
        purchaseCounts[sendAccountId] = purchaseCounts[sendAccountId].add(1);
        emit PurchaseCountIncremented(sendAccountId, purchaseCounts[sendAccountId]);

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account to check
     * @return bool True if account is active
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 isActive, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE", accountId)));
        require(bytes(err).length == 0, "Oracle error");
        return isActive == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 balance, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE", accountId)));
        require(bytes(err).length == 0, "Oracle error");
        return uint256(balance);
    }

    /**
     * @dev Allows owner to update the token contract address
     * @param newToken Address of the new token contract
     */
    function updateTokenContract(ITransferable newToken) external onlyOwner {
        require(address(newToken) != address(0), "Invalid token address");
        token = newToken;
    }

    /**
     * @dev Allows owner to update the oracle contract address
     * @param newOracle Address of the new oracle contract
     */
    function updateOracleContract(IOracle newOracle) external onlyOwner {
        require(address(newOracle) != address(0), "Invalid oracle address");
        oracle = newOracle;
    }

    /**
     * @dev Allows owner to manually set the purchase count for an account
     * @param accountId Account to update
     * @param count New purchase count
     */
    function setPurchaseCount(bytes32 accountId, uint256 count) external onlyOwner validAccountId(accountId) {
        purchaseCounts[accountId] = count;
        emit PurchaseCountIncremented(accountId, count);
    }

    /**
     * @dev Gets the current purchase count for an account
     * @param accountId Account to check
     * @return uint256 Current purchase count
     */
    function getPurchaseCount(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Allows owner to withdraw any stuck tokens in the contract
     * @param tokenAddress Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to send the tokens to
     */
    function withdrawStuckTokens(address tokenAddress, uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20 tokenContract = IERC20(tokenAddress);
        require(tokenContract.transfer(recipient, amount), "Token transfer failed");
    }

    // Additional helper functions and logic can be added here

    // END PART 1

Here's PART 2 of the smart contract implementation for the Discount contract:

// BEGIN PART 2

    using SafeMath for uint256;

    // Discount tiers
    struct DiscountTier {
        uint256 minPurchases;
        uint256 discountPercentage;
    }

    // Mapping to store discount tiers
    mapping(uint256 => DiscountTier) public discountTiers;

    // Number of discount tiers
    uint256 public discountTierCount;

    // Mapping to store user purchase counts
    mapping(bytes32 => uint256) public userPurchaseCounts;

    // Mapping to store item prices
    mapping(bytes32 => uint256) public itemPrices;

    // Minimum purchase amount for discount eligibility
    uint256 public constant MIN_PURCHASE_AMOUNT = 10 * 10**18; // 10 tokens

    // Maximum discount percentage
    uint256 public constant MAX_DISCOUNT_PERCENTAGE = 50; // 50%

    // Cooldown period between purchases (in seconds)
    uint256 public constant PURCHASE_COOLDOWN = 1 days;

    // Mapping to store last purchase timestamp for each user
    mapping(bytes32 => uint256) public lastPurchaseTimestamp;

    // Event emitted when discount tiers are updated
    event DiscountTiersUpdated(uint256 tierCount);

    // Event emitted when item price is updated
    event ItemPriceUpdated(bytes32 indexed item, uint256 price);

    // Event emitted when user purchase count is updated
    event UserPurchaseCountUpdated(bytes32 indexed user, uint256 count);

    /**
     * @dev Initializes discount tiers
     * @notice Only callable by admin
     */
    function initializeDiscountTiers() external onlyAdmin {
        require(discountTierCount == 0, "Discount tiers already initialized");

        discountTiers[1] = DiscountTier(0, 0);
        discountTiers[2] = DiscountTier(5, 5);
        discountTiers[3] = DiscountTier(10, 10);
        discountTiers[4] = DiscountTier(20, 15);
        discountTiers[5] = DiscountTier(50, 20);

        discountTierCount = 5;

        emit DiscountTiersUpdated(discountTierCount);
    }

    /**
     * @dev Updates discount tiers
     * @param _tiers Array of DiscountTier structs
     * @notice Only callable by admin
     */
    function updateDiscountTiers(DiscountTier[] memory _tiers) external onlyAdmin {
        require(_tiers.length > 0, "Must provide at least one tier");

        for (uint256 i = 0; i < _tiers.length; i++) {
            require(_tiers[i].discountPercentage <= MAX_DISCOUNT_PERCENTAGE, "Discount percentage too high");
            discountTiers[i + 1] = _tiers[i];
        }

        discountTierCount = _tiers.length;

        emit DiscountTiersUpdated(discountTierCount);
    }

    /**
     * @dev Sets price for an item
     * @param item Identifier of the item
     * @param price Price of the item
     * @notice Only callable by admin
     */
    function setItemPrice(bytes32 item, uint256 price) external onlyAdmin {
        require(item != bytes32(0), "Invalid item identifier");
        require(price > 0, "Price must be greater than zero");

        itemPrices[item] = price;

        emit ItemPriceUpdated(item, price);
    }

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");

        if (amount < MIN_PURCHASE_AMOUNT) {
            return amount;
        }

        uint256 discountPercentage = getDiscountPercentage(purchasedCounts);
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Gets discount percentage based on purchase count
     * @param purchasedCounts Number of previous purchases
     * @return Discount percentage
     */
    function getDiscountPercentage(uint256 purchasedCounts) internal view returns (uint256) {
        for (uint256 i = discountTierCount; i > 0; i--) {
            if (purchasedCounts >= discountTiers[i].minPurchases) {
                return discountTiers[i].discountPercentage;
            }
        }
        return 0;
    }

    /**
     * @dev Processes a purchase with discount
     * @param sendAccountId Account making the purchase
     * @param item Identifier of the item being purchased
     * @notice Updates user purchase count and applies discount
     */
    function processPurchase(bytes32 sendAccountId, bytes32 item) external {
        require(sendAccountId != bytes32(0), "Invalid send account");
        require(item != bytes32(0), "Invalid item identifier");
        require(block.timestamp >= lastPurchaseTimestamp[sendAccountId].add(PURCHASE_COOLDOWN), "Purchase cooldown not elapsed");

        uint256 itemPrice = itemPrices[item];
        require(itemPrice > 0, "Item price not set");

        uint256 purchasedCounts = userPurchaseCounts[sendAccountId];
        uint256 discountedAmount = discount(itemPrice, purchasedCounts);

        // Perform the transfer using the customTransfer function
        bool transferResult = customTransfer(
            sendAccountId,
            sendAccountId,
            bytes32(uint256(address(this))),
            discountedAmount,
            item,
            bytes32(0),
            "Discounted purchase",
            bytes32(block.timestamp)
        );

        require(transferResult, "Transfer failed");

        // Update user purchase count
        userPurchaseCounts[sendAccountId] = purchasedCounts.add(1);
        lastPurchaseTimestamp[sendAccountId] = block.timestamp;

        emit Discount(sendAccountId, item, itemPrice, discountedAmount);
        emit UserPurchaseCountUpdated(sendAccountId, userPurchaseCounts[sendAccountId]);
    }

    /**
     * @dev Gets user purchase count
     * @param accountId Account to query
     * @return Number of purchases made by the account
     */
    function getUserPurchaseCount(bytes32 accountId) external view returns (uint256) {
        return userPurchaseCounts[accountId];
    }

    /**
     * @dev Gets item price
     * @param item Identifier of the item
     * @return Price of the item
     */
    function getItemPrice(bytes32 item) external view returns (uint256) {
        return itemPrices[item];
    }

    /**
     * @dev Checks if user is eligible for discount
     * @param accountId Account to check
     * @param amount Purchase amount
     * @return True if eligible for discount, false otherwise
     */
    function isEligibleForDiscount(bytes32 accountId, uint256 amount) external view returns (bool) {
        return amount >= MIN_PURCHASE_AMOUNT && userPurchaseCounts[accountId] > 0;
    }

    /**
     * @dev Calculates potential savings for a purchase
     * @param accountId Account making the purchase
     * @param item Identifier of the item
     * @return Original price, discounted price, and savings
     */
    function calculatePotentialSavings(bytes32 accountId, bytes32 item) external view returns (uint256, uint256, uint256) {
        uint256 itemPrice = itemPrices[item];
        uint256 purchasedCounts = userPurchaseCounts[accountId];
        uint256 discountedAmount = discount(itemPrice, purchasedCounts);
        uint256 savings = itemPrice.sub(discountedAmount);

        return (itemPrice, discountedAmount, savings);
    }

    /**
     * @dev Gets time remaining until next purchase is allowed
     * @param accountId Account to check
     * @return Time in seconds until next purchase is allowed
     */
    function getTimeUntilNextPurchase(bytes32 accountId) external view returns (uint256) {
        uint256 lastPurchase = lastPurchaseTimestamp[accountId];
        if (lastPurchase == 0 || block.timestamp >= lastPurchase.add(PURCHASE_COOLDOWN)) {
            return 0;
        }
        return lastPurchase.add(PURCHASE_COOLDOWN).sub(block.timestamp);
    }

    /**
     * @dev Bulk update of item prices
     * @param items Array of item identifiers
     * @param prices Array of corresponding prices
     * @notice Only callable by admin
     */
    function bulkUpdateItemPrices(bytes32[] memory items, uint256[] memory prices) external onlyAdmin {
        require(items.length == prices.length, "Arrays must have equal length");
        for (uint256 i = 0; i < items.length; i++) {
            require(items[i] != bytes32(0), "Invalid item identifier");
            require(prices[i] > 0, "Price must be greater than zero");
            itemPrices[items[i]] = prices[i];
            emit ItemPriceUpdated(items[i], prices[i]);
        }
    }

    /**
     * @dev Resets purchase count for an account
     * @param accountId Account to reset
     * @notice Only callable by admin
     */
    function resetPurchaseCount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account identifier");
        userPurchaseCounts[accountId] = 0;
        emit UserPurchaseCountUpdated(accountId, 0);
    }

    /**
     * @dev Gets all discount tiers
     * @return Array of DiscountTier structs
     */
    function getAllDiscountTiers() external view returns (DiscountTier[] memory) {
        DiscountTier[] memory tiers = new DiscountTier[](discountTierCount);
        for (uint256 i = 1; i <= discountTierCount; i++) {
            tiers[i - 1] = discountTiers[i];
        }
        return tiers;
    }

    /**
     * @dev Checks if a specific discount tier exists
     * @param tier Tier number to check
     * @return True if tier exists, false otherwise
     */
    function discountTierExists(uint256 tier) external view returns (bool) {
        return tier > 0 && tier <= discountTierCount;
    }

    /**
     * @dev Gets the highest discount percentage available
     * @return Highest discount percentage
     */
    function getHighestDiscountPercentage() external view returns (uint256) {
        uint256 highest = 0;
        for (uint256 i = 1; i <= discountTierCount; i++) {
            if (discountTiers[i].discountPercentage > highest) {
                highest = discountTiers[i].discountPercentage;
            }
        }
        return highest;
    }

    /**
     * @dev Calculates the number of purchases needed for next discount tier
     * @param accountId Account to check
     * @return Number of purchases needed, 0 if already at highest tier
     */
    function purchasesNeededForNextTier(bytes32 accountId) external view returns (uint256) {
        uint256 currentCount = userPurchaseCounts[accountId];
        for (uint256 i = 1; i <= discountTierCount; i++) {
            if (currentCount < discountTiers[i].minPurchases) {
                return discountTiers[i].minPurchases.sub(currentCount);
            }
        }
        return 0; // Already at highest tier
    }

    /**
     * @dev Applies a one-time bonus discount to an account
     * @param accountId Account to receive bonus
     * @param bonusPercentage Additional discount percentage
     * @notice Only callable by admin
     */
    function applyBonusDiscount(bytes32 accountId, uint256 bonusPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account identifier");
        require(bonusPercentage > 0 && bonusPercentage <= MAX_DISCOUNT_PERCENTAGE, "Invalid bonus percentage");

        // Implementation of bonus discount logic
        // This could involve creating a separate mapping for bonus discounts
        // or modifying the existing discount calculation logic
    }

    /**
     * @dev Checks if an item is eligible for discount
     * @param item Identifier of the item
     * @return True if eligible, false otherwise
     */
    function isItemEligibleForDiscount(bytes32 item) external view returns (bool) {
        return itemPrices[item] >= MIN_PURCHASE_AMOUNT;
    }

    // Additional helper functions and internal logic...

// END PART 2

// BEGIN PART 3

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

        uint256 discountRate;
        if (purchasedCounts == 0) {
            discountRate = 0; // No discount for first-time buyers
        } else if (purchasedCounts < 5) {
            discountRate = 5; // 5% discount for 1-4 purchases
        } else if (purchasedCounts < 10) {
            discountRate = 10; // 10% discount for 5-9 purchases
        } else if (purchasedCounts < 20) {
            discountRate = 15; // 15% discount for 10-19 purchases
        } else {
            discountRate = 20; // 20% discount for 20+ purchases
        }

        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to apply discount and execute transfer
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by the account
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return bool indicating if the discounted transfer was successful
     */
    function applyDiscountAndTransfer(
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

        bool transferResult = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            bytes32(0),
            bytes32(0),
            memo,
            traceId
        );

        if (transferResult) {
            emit Discount(sendAccountId, item, amount, discountedAmount);
        }

        return transferResult;
    }

    /**
     * @dev Updates the purchase count for an account
     * @param accountId The account to update
     */
    function incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Retrieves the current discount rate from the oracle
     * @return The current discount rate as a percentage
     */
    function getCurrentDiscountRate() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to retrieve discount rate");
        return uint256(value);
    }

    /**
     * @dev Applies a dynamic discount based on the current oracle rate
     * @param amount The original amount
     * @return The discounted amount
     */
    function applyDynamicDiscount(uint256 amount) internal view returns (uint256) {
        uint256 discountRate = getCurrentDiscountRate();
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Checks if an account is eligible for a special promotion
     * @param accountId The account to check
     * @return bool indicating if the account is eligible
     */
    function isEligibleForPromotion(bytes32 accountId) internal view returns (bool) {
        return purchaseCounts[accountId] % 10 == 0; // Every 10th purchase is eligible
    }

    /**
     * @dev Applies a promotional discount if the account is eligible
     * @param accountId The account making the purchase
     * @param amount The original purchase amount
     * @return The amount after applying any promotional discount
     */
    function applyPromotionalDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        if (isEligibleForPromotion(accountId)) {
            return amount.mul(75).div(100); // 25% off for promotional discount
        }
        return amount;
    }

    /**
     * @dev Calculates loyalty points based on purchase amount
     * @param amount The purchase amount
     * @return The number of loyalty points earned
     */
    function calculateLoyaltyPoints(uint256 amount) internal pure returns (uint256) {
        return amount.div(100); // 1 point per 100 units of currency spent
    }

    /**
     * @dev Awards loyalty points to an account
     * @param accountId The account to award points to
     * @param amount The purchase amount
     */
    function awardLoyaltyPoints(bytes32 accountId, uint256 amount) internal {
        uint256 points = calculateLoyaltyPoints(amount);
        loyaltyPoints[accountId] = loyaltyPoints[accountId].add(points);
    }

    /**
     * @dev Checks if an account has enough loyalty points for a reward
     * @param accountId The account to check
     * @return bool indicating if the account is eligible for a reward
     */
    function isEligibleForLoyaltyReward(bytes32 accountId) internal view returns (bool) {
        return loyaltyPoints[accountId] >= LOYALTY_REWARD_THRESHOLD;
    }

    /**
     * @dev Redeems loyalty points for a discount
     * @param accountId The account redeeming points
     * @param amount The original purchase amount
     * @return The discounted amount after applying loyalty reward
     */
    function redeemLoyaltyDiscount(bytes32 accountId, uint256 amount) internal returns (uint256) {
        if (isEligibleForLoyaltyReward(accountId)) {
            loyaltyPoints[accountId] = loyaltyPoints[accountId].sub(LOYALTY_REWARD_THRESHOLD);
            return amount.mul(90).div(100); // 10% discount for loyalty reward
        }
        return amount;
    }

    /**
     * @dev Checks if a purchase qualifies for bulk discount
     * @param amount The purchase amount
     * @return bool indicating if the purchase qualifies for bulk discount
     */
    function qualifiesForBulkDiscount(uint256 amount) internal pure returns (bool) {
        return amount >= BULK_PURCHASE_THRESHOLD;
    }

    /**
     * @dev Applies bulk discount to large purchases
     * @param amount The original purchase amount
     * @return The discounted amount after applying bulk discount
     */
    function applyBulkDiscount(uint256 amount) internal pure returns (uint256) {
        if (qualifiesForBulkDiscount(amount)) {
            return amount.mul(95).div(100); // 5% discount for bulk purchases
        }
        return amount;
    }

    /**
     * @dev Checks if it's a special discount day
     * @return bool indicating if today is a special discount day
     */
    function isSpecialDiscountDay() internal view returns (bool) {
        // Example: Every 15th day of the month is a special discount day
        return (block.timestamp / 86400) % 30 == 15;
    }

    /**
     * @dev Applies special day discount if applicable
     * @param amount The original purchase amount
     * @return The discounted amount after applying special day discount
     */
    function applySpecialDayDiscount(uint256 amount) internal view returns (uint256) {
        if (isSpecialDiscountDay()) {
            return amount.mul(90).div(100); // 10% discount on special days
        }
        return amount;
    }

    /**
     * @dev Calculates the final discounted amount considering all factors
     * @param sendAccountId The account making the purchase
     * @param amount The original purchase amount
     * @return The final discounted amount
     */
    function calculateFinalDiscount(bytes32 sendAccountId, uint256 amount) internal returns (uint256) {
        uint256 discountedAmount = amount;

        // Apply base discount based on purchase history
        discountedAmount = discount(discountedAmount, purchaseCounts[sendAccountId]);

        // Apply dynamic discount from oracle
        discountedAmount = applyDynamicDiscount(discountedAmount);

        // Apply promotional discount if eligible
        discountedAmount = applyPromotionalDiscount(sendAccountId, discountedAmount);

        // Apply loyalty discount if eligible
        discountedAmount = redeemLoyaltyDiscount(sendAccountId, discountedAmount);

        // Apply bulk purchase discount
        discountedAmount = applyBulkDiscount(discountedAmount);

        // Apply special day discount
        discountedAmount = applySpecialDayDiscount(discountedAmount);

        return discountedAmount;
    }

    /**
     * @dev Executes a purchase with all applicable discounts
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return bool indicating if the purchase was successful
     */
    function executePurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) public returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid send account");
        require(fromAccountId != bytes32(0), "Invalid from account");
        require(toAccountId != bytes32(0), "Invalid to account");
        require(amount > 0, "Amount must be greater than zero");

        uint256 finalAmount = calculateFinalDiscount(sendAccountId, amount);

        bool transferResult = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            finalAmount,
            bytes32(0),
            bytes32(0),
            memo,
            traceId
        );

        if (transferResult) {
            emit Discount(sendAccountId, item, amount, finalAmount);
            incrementPurchaseCount(sendAccountId);
            awardLoyaltyPoints(sendAccountId, finalAmount);
        }

        return transferResult;
    }

    /**
     * @dev Retrieves the purchase history count for an account
     * @param accountId The account to check
     * @return The number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) public view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Retrieves the loyalty points balance for an account
     * @param accountId The account to check
     * @return The number of loyalty points accumulated by the account
     */
    function getLoyaltyPoints(bytes32 accountId) public view returns (uint256) {
        return loyaltyPoints[accountId];
    }

    /**
     * @dev Allows an admin to manually adjust loyalty points
     * @param accountId The account to adjust
     * @param points The number of points to add (or subtract if negative)
     */
    function adjustLoyaltyPoints(bytes32 accountId, int256 points) public onlyAdmin {
        require(accountId != bytes32(0), "Invalid account");
        
        if (points >= 0) {
            loyaltyPoints[accountId] = loyaltyPoints[accountId].add(uint256(points));
        } else {
            uint256 absPoints = uint256(-points);
            require(loyaltyPoints[accountId] >= absPoints, "Insufficient loyalty points");
            loyaltyPoints[accountId] = loyaltyPoints[accountId].sub(absPoints);
        }
    }

    /**
     * @dev Allows an admin to set a custom discount rate for a specific account
     * @param accountId The account to set the custom rate for
     * @param rate The custom discount rate (0-100)
     */
    function setCustomDiscountRate(bytes32 accountId, uint256 rate) public onlyAdmin {
        require(accountId != bytes32(0), "Invalid account");
        require(rate <= 100, "Invalid discount rate");
        customDiscountRates[accountId] = rate;
    }

    /**
     * @dev Retrieves the custom discount rate for an account
     * @param accountId The account to check
     * @return The custom discount rate for the account (0 if not set)
     */
    function getCustomDiscountRate(bytes32 accountId) public view returns (uint256) {
        return customDiscountRates[accountId];
    }

    /**
     * @dev Applies the custom discount rate if set for an account
     * @param accountId The account making the purchase
     * @param amount The original purchase amount
     * @return The discounted amount after applying custom rate
     */
    function applyCustomDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        uint256 customRate = customDiscountRates[accountId];
        if (customRate > 0) {
            return amount.mul(100 - customRate).div(100);
        }
        return amount;
    }

    /**
     * @dev Sets a temporary promotional discount for all purchases
     * @param rate The promotional discount rate (0-100)
     * @param duration The duration of the promotion in seconds
     */
    function setPromotionalDiscount(uint256 rate, uint256 duration) public onlyAdmin {
        require(rate <= 100, "Invalid discount rate");
        promotionalDiscount = rate;
        promotionalDiscountEnd = block.timestamp + duration;
    }

    /**
     * @dev Applies the current promotional discount if active
     * @param amount The original purchase amount
     * @return The discounted amount after applying promotional discount
     */
    function applyPromotionalDiscount(uint256 amount) internal view returns (uint256) {
        if (block.timestamp < promotionalDiscountEnd) {
            return amount.mul(100 - promotionalDiscount).div(100);
        }
        return amount;
    }

    /**
     * @dev Cancels the current promotional discount
     */
    function cancelPromotionalDiscount() public onlyAdmin {
        promotionalDiscount = 0;
        promotionalDiscountEnd = 0;
    }

    /**
     * @dev Retrieves the current promotional discount information
     * @return rate The current promotional discount rate
     * @return endTime The end time of the current promotion (0 if not active)
     */
    function getPromotionalDiscount() public view returns (uint256 rate, uint256 endTime) {
        return (promotionalDiscount, promotionalDiscountEnd);
    }

    /**
     * @dev Sets a discount tier for a specific purchase volume
     * @param minAmount The minimum purchase amount for this tier
     * @param discountRate The discount rate for this tier (0-100)
     */
    function setVolumeTierDiscount(uint256 minAmount, uint256 discountRate) public onlyAdmin {
        require(discountRate <= 100, "Invalid discount rate");
        volumeTierDiscounts[minAmount] = discountRate;
    }

    /**
     * @dev Removes a volume discount tier
     * @param minAmount The minimum purchase amount tier to remove
     */
    function removeVolumeTierDiscount(uint256 minAmount) public onlyAdmin {
        delete volumeTierDiscounts[minAmount];
    }

    /**
     * @dev Applies volume-based tier discount
     * @param amount The original purchase amount
     * @return The disc