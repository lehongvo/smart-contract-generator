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
    
    // Discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount
    
    // Events
    event OracleUpdated(uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyActiveOracle(uint256 _oracleId) {
        require(_oracleId > 0, "Invalid oracle ID");
        (bytes32 isActive, string memory err) = oracle.get(_oracleId, "IS_ACTIVE");
        require(isActive == bytes32(uint256(1)), string(abi.encodePacked("Oracle not active: ", err)));
        _;
    }

    modifier validAccount(bytes32 accountId) {
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
        oracleId = 1; // Default oracle ID, can be updated later
        
        // Initialize Ownable
        _transferOwnership(msg.sender);
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
    function setOracleId(uint256 _oracleId) external onlyOwner onlyActiveOracle(_oracleId) {
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
    ) external override nonReentrant returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Check if accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance of source account
        uint256 balance = getAccountBalance(fromAccountId);
        require(balance >= amount, "Insufficient balance in source account");

        // Apply discount based on purchase history
        uint256 purchaseCount = purchaseCounts[sendAccountId];
        uint256 discountedAmount = this.discount(amount, purchaseCount);

        // Perform the transfer
        bool transferResult = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            miscValue1,
            miscValue2,
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        // Increment purchase count
        purchaseCounts[sendAccountId] = purchaseCount.add(1);
        emit PurchaseCountIncremented(sendAccountId, purchaseCounts[sendAccountId]);

        // Emit discount event
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        // Emit custom transfer event
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);

        return true;
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account to check
     * @return bool True if account is active
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 isActive, ) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE_", accountId)));
        return isActive == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 balance, ) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE_", accountId)));
        return uint256(balance);
    }

    // Additional helper functions can be added here

    // END PART 1

// BEGIN PART 2

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
        uint256 finalAmount = amount.sub(discountAmount);

        return finalAmount;
    }

    /**
     * @dev Applies discount to a purchase and executes transfer
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the discounted purchase was successful
     */
    function discountedPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(item != bytes32(0), "Invalid item identifier");

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

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchasedCounts Number of previous purchases by account
     * @return discountRate Current discount rate as a percentage
     */
    function getDiscountRate(uint256 purchasedCounts) external pure returns (uint256 discountRate) {
        if (purchasedCounts == 0) {
            return 0;
        } else if (purchasedCounts < 5) {
            return 5;
        } else if (purchasedCounts < 10) {
            return 10;
        } else if (purchasedCounts < 20) {
            return 15;
        } else {
            return 20;
        }
    }

    /**
     * @dev Calculates the savings from a discounted purchase
     * @param originalAmount Original purchase amount before discount
     * @param discountedAmount Final amount after discount applied
     * @return savings Amount saved due to discount
     */
    function calculateSavings(uint256 originalAmount, uint256 discountedAmount) external pure returns (uint256 savings) {
        require(originalAmount >= discountedAmount, "Invalid amounts");
        return originalAmount.sub(discountedAmount);
    }

    /**
     * @dev Retrieves the purchase history for an account
     * @param accountId Account to query
     * @return purchasedCounts Number of purchases made by the account
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 purchasedCounts) {
        require(accountId != bytes32(0), "Invalid accountId");
        return purchaseHistory[accountId];
    }

    /**
     * @dev Updates the purchase history for an account
     * @param accountId Account to update
     * @param newPurchaseCount New total purchase count
     * @notice Only callable by authorized addresses
     */
    function updatePurchaseHistory(bytes32 accountId, uint256 newPurchaseCount) external onlyAuthorized {
        require(accountId != bytes32(0), "Invalid accountId");
        require(newPurchaseCount >= purchaseHistory[accountId], "Cannot decrease purchase count");
        purchaseHistory[accountId] = newPurchaseCount;
        emit PurchaseHistoryUpdated(accountId, newPurchaseCount);
    }

    /**
     * @dev Applies a special one-time discount to an account
     * @param accountId Account to receive the special discount
     * @param discountPercentage Percentage of the special discount
     * @notice Only callable by admin
     */
    function applySpecialDiscount(bytes32 accountId, uint256 discountPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountPercentage > 0 && discountPercentage <= 100, "Invalid discount percentage");
        specialDiscounts[accountId] = discountPercentage;
        emit SpecialDiscountApplied(accountId, discountPercentage);
    }

    /**
     * @dev Removes a special discount from an account
     * @param accountId Account to remove the special discount from
     * @notice Only callable by admin
     */
    function removeSpecialDiscount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(specialDiscounts[accountId] > 0, "No special discount exists");
        delete specialDiscounts[accountId];
        emit SpecialDiscountRemoved(accountId);
    }

    /**
     * @dev Retrieves the special discount rate for an account
     * @param accountId Account to query
     * @return discountPercentage Special discount percentage, 0 if none exists
     */
    function getSpecialDiscount(bytes32 accountId) external view returns (uint256 discountPercentage) {
        require(accountId != bytes32(0), "Invalid accountId");
        return specialDiscounts[accountId];
    }

    /**
     * @dev Sets a new discount tier
     * @param tier Tier level
     * @param minPurchases Minimum number of purchases required for this tier
     * @param discountPercentage Discount percentage for this tier
     * @notice Only callable by admin
     */
    function setDiscountTier(uint256 tier, uint256 minPurchases, uint256 discountPercentage) external onlyAdmin {
        require(tier > 0, "Invalid tier");
        require(discountPercentage <= 100, "Invalid discount percentage");
        discountTiers[tier] = DiscountTier(minPurchases, discountPercentage);
        emit DiscountTierUpdated(tier, minPurchases, discountPercentage);
    }

    /**
     * @dev Retrieves a discount tier
     * @param tier Tier level to query
     * @return minPurchases Minimum purchases for this tier
     * @return discountPercentage Discount percentage for this tier
     */
    function getDiscountTier(uint256 tier) external view returns (uint256 minPurchases, uint256 discountPercentage) {
        require(tier > 0, "Invalid tier");
        DiscountTier memory discountTier = discountTiers[tier];
        return (discountTier.minPurchases, discountTier.discountPercentage);
    }

    /**
     * @dev Calculates the discount using the tiered system
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return discountedAmount Final amount after applying tiered discount
     */
    function calculateTieredDiscount(uint256 amount, uint256 purchasedCounts) public view returns (uint256 discountedAmount) {
        uint256 highestTier = 0;
        uint256 highestDiscount = 0;

        for (uint256 i = 1; i <= maxTier; i++) {
            if (purchasedCounts >= discountTiers[i].minPurchases && discountTiers[i].discountPercentage > highestDiscount) {
                highestTier = i;
                highestDiscount = discountTiers[i].discountPercentage;
            }
        }

        if (highestTier == 0) {
            return amount; // No discount applicable
        }

        uint256 discountAmount = amount.mul(highestDiscount).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Applies a bulk discount to multiple items
     * @param items Array of item identifiers
     * @param amounts Array of original amounts for each item
     * @param accountId Account making the bulk purchase
     * @return discountedAmounts Array of discounted amounts for each item
     * @return totalSavings Total amount saved from the bulk discount
     */
    function applyBulkDiscount(bytes32[] memory items, uint256[] memory amounts, bytes32 accountId) 
        external 
        view 
        returns (uint256[] memory discountedAmounts, uint256 totalSavings) 
    {
        require(items.length == amounts.length, "Array lengths must match");
        require(items.length > 0, "Must provide at least one item");
        require(accountId != bytes32(0), "Invalid accountId");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            totalAmount = totalAmount.add(amounts[i]);
        }

        uint256 purchasedCounts = purchaseHistory[accountId];
        uint256 bulkDiscountPercentage = calculateBulkDiscountPercentage(items.length);

        discountedAmounts = new uint256[](items.length);
        totalSavings = 0;

        for (uint256 i = 0; i < items.length; i++) {
            uint256 itemDiscount = calculateTieredDiscount(amounts[i], purchasedCounts);
            uint256 bulkDiscount = amounts[i].mul(bulkDiscountPercentage).div(100);
            uint256 finalDiscount = (itemDiscount < bulkDiscount) ? bulkDiscount : itemDiscount;

            discountedAmounts[i] = amounts[i].sub(finalDiscount);
            totalSavings = totalSavings.add(finalDiscount);
        }

        return (discountedAmounts, totalSavings);
    }

    /**
     * @dev Calculates the bulk discount percentage based on the number of items
     * @param itemCount Number of items in the bulk purchase
     * @return discountPercentage Percentage discount for the bulk purchase
     */
    function calculateBulkDiscountPercentage(uint256 itemCount) public pure returns (uint256 discountPercentage) {
        if (itemCount < 5) {
            return 0; // No bulk discount for less than 5 items
        } else if (itemCount < 10) {
            return 5; // 5% discount for 5-9 items
        } else if (itemCount < 20) {
            return 10; // 10% discount for 10-19 items
        } else {
            return 15; // 15% discount for 20 or more items
        }
    }

    /**
     * @dev Applies a time-limited discount to an account
     * @param accountId Account to receive the time-limited discount
     * @param discountPercentage Percentage of the time-limited discount
     * @param duration Duration of the discount in seconds
     * @notice Only callable by admin
     */
    function applyTimeLimitedDiscount(bytes32 accountId, uint256 discountPercentage, uint256 duration) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountPercentage > 0 && discountPercentage <= 100, "Invalid discount percentage");
        require(duration > 0, "Invalid duration");

        uint256 expirationTime = block.timestamp.add(duration);
        timeLimitedDiscounts[accountId] = TimeLimitedDiscount(discountPercentage, expirationTime);
        emit TimeLimitedDiscountApplied(accountId, discountPercentage, expirationTime);
    }

    /**
     * @dev Retrieves the time-limited discount for an account
     * @param accountId Account to query
     * @return discountPercentage Time-limited discount percentage, 0 if none exists or expired
     * @return expirationTime Expiration timestamp of the discount
     */
    function getTimeLimitedDiscount(bytes32 accountId) external view returns (uint256 discountPercentage, uint256 expirationTime) {
        require(accountId != bytes32(0), "Invalid accountId");
        TimeLimitedDiscount memory discount = timeLimitedDiscounts[accountId];
        
        if (discount.expirationTime > block.timestamp) {
            return (discount.discountPercentage, discount.expirationTime);
        } else {
            return (0, 0);
        }
    }

    /**
     * @dev Removes an expired time-limited discount
     * @param accountId Account to remove the expired discount from
     * @notice Can be called by anyone to clean up expired discounts
     */
    function removeExpiredTimeLimitedDiscount(bytes32 accountId) external {
        require(accountId != bytes32(0), "Invalid accountId");
        TimeLimitedDiscount memory discount = timeLimitedDiscounts[accountId];

        if (discount.expirationTime <= block.timestamp && discount.expirationTime != 0) {
            delete timeLimitedDiscounts[accountId];
            emit TimeLimitedDiscountExpired(accountId);
        }
    }

    /**
     * @dev Applies a referral discount to an account
     * @param referrer Account that referred the new customer
     * @param referee New customer account being referred
     * @param referralDiscountPercentage Discount percentage for the referee
     * @param referrerBonus Bonus amount or percentage for the referrer
     * @notice Only callable by authorized addresses
     */
    function applyReferralDiscount(
        bytes32 referrer, 
        bytes32 referee, 
        uint256 referralDiscountPercentage, 
        uint256 referrerBonus
    ) external onlyAuthorized {
        require(referrer != bytes32(0) && referee != bytes32(0), "Invalid account IDs");
        require(referralDiscountPercentage <= 100, "Invalid discount percentage");
        
        referralDiscounts[referee] = ReferralDiscount(referrer, referralDiscountPercentage);
        referrerBonuses[referrer] = referrerBonuses[referrer].add(referrerBonus);

        emit ReferralDiscountApplied(referrer, referee, referralDiscountPercentage, referrerBonus);
    }

    /**
     * @dev Retrieves the referral discount for an account
     * @param accountId Account to query
     * @return referrer Address of the referrer
     *

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
        require(amount > 0, "Amount must be greater than 0");

        uint256 discountRate;
        if (purchasedCounts < 5) {
            discountRate = 5; // 5% discount for first 5 purchases
        } else if (purchasedCounts < 10) {
            discountRate = 10; // 10% discount for 6-10 purchases
        } else if (purchasedCounts < 20) {
            discountRate = 15; // 15% discount for 11-20 purchases
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
     * @param item Identifier of the purchased item
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if transfer completed successfully
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
    ) internal returns (bool result) {
        uint256 discountedAmount = discount(amount, purchasedCounts);
        
        result = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(0),
            memo,
            traceId
        );

        require(result, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);
        return result;
    }

    /**
     * @dev Executes a discounted purchase
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the purchased item
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if purchase completed successfully
     */
    function executePurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        return _applyDiscountAndTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            amount,
            item,
            purchasedCounts,
            memo,
            traceId
        );
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchasedCounts Number of previous purchases by account
     * @return discountRate Current discount rate as a percentage
     */
    function getDiscountRate(uint256 purchasedCounts) external pure returns (uint256 discountRate) {
        if (purchasedCounts < 5) {
            return 5;
        } else if (purchasedCounts < 10) {
            return 10;
        } else if (purchasedCounts < 20) {
            return 15;
        } else {
            return 20;
        }
    }

    /**
     * @dev Calculates the savings from a discount
     * @param originalAmount Original purchase amount
     * @param discountedAmount Final amount after discount
     * @return savings Amount saved due to discount
     */
    function calculateSavings(uint256 originalAmount, uint256 discountedAmount) external pure returns (uint256 savings) {
        require(originalAmount >= discountedAmount, "Invalid amounts");
        return originalAmount.sub(discountedAmount);
    }

    /**
     * @dev Checks if an account is eligible for a special promotion
     * @param accountId Account to check for eligibility
     * @return isEligible True if the account is eligible for a promotion
     */
    function isEligibleForPromotion(bytes32 accountId) external view returns (bool isEligible) {
        require(accountId != bytes32(0), "Invalid accountId");
        
        // Example logic: Check if the account has made a purchase in the last 30 days
        uint256 lastPurchaseTimestamp = getLastPurchaseTimestamp(accountId);
        return (block.timestamp - lastPurchaseTimestamp) <= 30 days;
    }

    /**
     * @dev Retrieves the timestamp of the last purchase for an account
     * @param accountId Account to check
     * @return timestamp Timestamp of the last purchase, or 0 if no purchases
     */
    function getLastPurchaseTimestamp(bytes32 accountId) internal view returns (uint256 timestamp) {
        // Implementation would depend on how purchase history is stored
        // This is a placeholder implementation
        return 0;
    }

    /**
     * @dev Applies a special promotional discount
     * @param amount Original purchase amount
     * @return promotionalAmount Discounted amount after applying the promotion
     */
    function applyPromotionalDiscount(uint256 amount) external view returns (uint256 promotionalAmount) {
        require(amount > 0, "Amount must be greater than 0");

        // Example: Get the promotional discount rate from the oracle
        (bytes32 promoRateBytes, string memory err) = oracle.get(oracleId, "PROMO_DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to get promotional rate");

        uint256 promoRate = uint256(promoRateBytes);
        require(promoRate > 0 && promoRate <= 100, "Invalid promotional rate");

        uint256 discountAmount = amount.mul(promoRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Checks if a specific item is eligible for a discount
     * @param item Identifier of the item to check
     * @return isEligible True if the item is eligible for a discount
     */
    function isItemEligibleForDiscount(bytes32 item) external view returns (bool isEligible) {
        require(item != bytes32(0), "Invalid item identifier");

        // Example: Check if the item is in the list of discountable items
        (bytes32 eligibilityBytes, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ITEM_ELIGIBLE_", item)));
        require(bytes(err).length == 0, "Failed to check item eligibility");

        return eligibilityBytes != bytes32(0);
    }

    /**
     * @dev Calculates the total discount amount for multiple items
     * @param items Array of item identifiers
     * @param amounts Array of corresponding purchase amounts
     * @param purchasedCounts Array of purchase counts for each item
     * @return totalDiscount Sum of all discounts applied
     */
    function calculateBulkDiscount(
        bytes32[] memory items,
        uint256[] memory amounts,
        uint256[] memory purchasedCounts
    ) external pure returns (uint256 totalDiscount) {
        require(items.length == amounts.length && amounts.length == purchasedCounts.length, "Array lengths must match");

        for (uint256 i = 0; i < items.length; i++) {
            uint256 originalAmount = amounts[i];
            uint256 discountedAmount = discount(originalAmount, purchasedCounts[i]);
            totalDiscount = totalDiscount.add(originalAmount.sub(discountedAmount));
        }

        return totalDiscount;
    }

    /**
     * @dev Executes a bulk purchase with discounts applied
     * @param sendAccountId Account initiating the purchases
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param items Array of item identifiers
     * @param amounts Array of corresponding purchase amounts
     * @param purchasedCounts Array of purchase counts for each item
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if all purchases completed successfully
     */
    function executeBulkPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        bytes32[] memory items,
        uint256[] memory amounts,
        uint256[] memory purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(items.length == amounts.length && amounts.length == purchasedCounts.length, "Array lengths must match");
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 totalDiscountedAmount = 0;

        for (uint256 i = 0; i < items.length; i++) {
            uint256 discountedAmount = discount(amounts[i], purchasedCounts[i]);
            totalDiscountedAmount = totalDiscountedAmount.add(discountedAmount);

            emit Discount(sendAccountId, items[i], amounts[i], discountedAmount);
        }

        success = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            totalDiscountedAmount,
            bytes32(0),
            bytes32(0),
            memo,
            traceId
        );

        require(success, "Bulk transfer failed");
        return success;
    }

    /**
     * @dev Retrieves the discount history for an account
     * @param accountId Account to check
     * @return totalDiscounts Total number of discounts applied
     * @return totalSavings Total amount saved from discounts
     */
    function getDiscountHistory(bytes32 accountId) external view returns (uint256 totalDiscounts, uint256 totalSavings) {
        require(accountId != bytes32(0), "Invalid accountId");

        // This would typically involve querying a mapping or other data structure
        // Placeholder implementation
        totalDiscounts = 0;
        totalSavings = 0;
    }

    /**
     * @dev Checks if an account is eligible for a loyalty bonus
     * @param accountId Account to check
     * @return isEligible True if the account is eligible for a loyalty bonus
     * @return bonusRate The bonus rate as a percentage
     */
    function checkLoyaltyBonus(bytes32 accountId) external view returns (bool isEligible, uint256 bonusRate) {
        require(accountId != bytes32(0), "Invalid accountId");

        // Example: Check total purchase amount and apply bonus tiers
        uint256 totalPurchaseAmount = getTotalPurchaseAmount(accountId);

        if (totalPurchaseAmount >= 10000 ether) {
            return (true, 5); // 5% bonus
        } else if (totalPurchaseAmount >= 5000 ether) {
            return (true, 3); // 3% bonus
        } else if (totalPurchaseAmount >= 1000 ether) {
            return (true, 1); // 1% bonus
        }

        return (false, 0);
    }

    /**
     * @dev Retrieves the total purchase amount for an account
     * @param accountId Account to check
     * @return totalAmount Total amount of all purchases
     */
    function getTotalPurchaseAmount(bytes32 accountId) internal view returns (uint256 totalAmount) {
        // Implementation would depend on how purchase history is stored
        // This is a placeholder implementation
        return 0;
    }

    /**
     * @dev Applies a loyalty bonus to a purchase
     * @param accountId Account making the purchase
     * @param amount Original purchase amount
     * @return bonusAmount Additional bonus amount to be credited
     */
    function applyLoyaltyBonus(bytes32 accountId, uint256 amount) external view returns (uint256 bonusAmount) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(amount > 0, "Amount must be greater than 0");

        (bool isEligible, uint256 bonusRate) = checkLoyaltyBonus(accountId);

        if (isEligible) {
            bonusAmount = amount.mul(bonusRate).div(100);
        } else {
            bonusAmount = 0;
        }

        return bonusAmount;
    }

    /**
     * @dev Executes a purchase with loyalty bonus applied
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the purchased item
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description/reason
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if purchase and bonus application completed successfully
     */
    function executePurchaseWithLoyaltyBonus(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Apply discount
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Apply loyalty bonus
        uint256 bonusAmount = applyLoyaltyBonus(sendAccountId, discountedAmount);

        // Execute the discounted transfer
        result = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(0),
            memo,
            traceId
        );

        require(result, "Transfer failed");

        // Credit the loyalty bonus if applicable
        if (bonusAmount > 0) {
            result = token.customTransfer(
                bytes32(0), // System account
                toAccountId, // Merchant pays the bonus
                sendAccountId, // Customer receives the bonus
                bonus