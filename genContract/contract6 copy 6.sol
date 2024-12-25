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
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    // Discount percentages (in basis points, 100 = 1%)
    uint256 private constant TIER1_DISCOUNT = 500; // 5%
    uint256 private constant TIER2_DISCOUNT = 1000; // 10%
    uint256 private constant TIER3_DISCOUNT = 1500; // 15%
    uint256 private constant MAX_DISCOUNT = 2000; // 20%
    
    // Events
    event OracleUpdated(uint256 oldOracleId, uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 accountId, uint256 newCount);

    // Modifiers
    modifier validAddress(address _address) {
        require(_address != address(0), "Invalid address: zero address not allowed");
        _;
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, "Invalid amount: must be greater than zero");
        _;
    }

    modifier validAccountId(bytes32 _accountId) {
        require(_accountId != bytes32(0), "Invalid accountId: must not be empty");
        _;
    }

    // Constructor
    constructor() {
        _disableInitializers();
    }

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
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;
        
        // Tiered discount structure based on purchase history
        if (purchasedCounts >= 100) {
            discountPercentage = 20; // 20% discount for 100+ purchases
        } else if (purchasedCounts >= 50) {
            discountPercentage = 15; // 15% discount for 50-99 purchases
        } else if (purchasedCounts >= 25) {
            discountPercentage = 10; // 10% discount for 25-49 purchases
        } else if (purchasedCounts >= 10) {
            discountPercentage = 5; // 5% discount for 10-24 purchases
        } else {
            discountPercentage = 0; // No discount for less than 10 purchases
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        uint256 finalAmount = amount.sub(discountAmount);

        return finalAmount;
    }

    /**
     * @dev Applies discount to a purchase and executes the transfer
     * @param sendAccountId Account making the purchase
     * @param item Identifier of the item being purchased
     * @param amount Original price of the item
     * @return success True if the discounted purchase was successful
     */
    function applyDiscountAndPurchase(bytes32 sendAccountId, bytes32 item, uint256 amount) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(item != bytes32(0), "Invalid item identifier");
        require(amount > 0, "Amount must be greater than zero");

        // Get the purchase count for the account
        uint256 purchaseCount = purchaseCounts[sendAccountId];

        // Calculate the discounted amount
        uint256 discountedAmount = discount(amount, purchaseCount);

        // Perform the transfer using the token contract
        bool transferResult = token.customTransfer(
            sendAccountId,
            sendAccountId,
            treasuryAccount,
            discountedAmount,
            item,
            bytes32(0),
            "Discounted purchase",
            keccak256(abi.encodePacked(sendAccountId, item, block.timestamp))
        );

        require(transferResult, "Transfer failed");

        // Increment the purchase count for the account
        purchaseCounts[sendAccountId] = purchaseCount.add(1);

        // Emit the Discount event
        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Retrieves the current discount rate for a given account
     * @param accountId The account to check the discount rate for
     * @return discountRate The current discount rate as a percentage
     */
    function getCurrentDiscountRate(bytes32 accountId) external view returns (uint256 discountRate) {
        require(accountId != bytes32(0), "Invalid account ID");

        uint256 purchaseCount = purchaseCounts[accountId];

        if (purchaseCount >= 100) {
            return 20;
        } else if (purchaseCount >= 50) {
            return 15;
        } else if (purchaseCount >= 25) {
            return 10;
        } else if (purchaseCount >= 10) {
            return 5;
        } else {
            return 0;
        }
    }

    /**
     * @dev Allows admin to set a custom discount rate for a specific account
     * @param accountId The account to set the custom discount for
     * @param discountRate The custom discount rate as a percentage
     */
    function setCustomDiscountRate(bytes32 accountId, uint256 discountRate) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");

        customDiscountRates[accountId] = discountRate;
        emit CustomDiscountRateSet(accountId, discountRate);
    }

    /**
     * @dev Removes a custom discount rate for a specific account
     * @param accountId The account to remove the custom discount from
     */
    function removeCustomDiscountRate(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        require(customDiscountRates[accountId] > 0, "No custom discount rate set for this account");

        delete customDiscountRates[accountId];
        emit CustomDiscountRateRemoved(accountId);
    }

    /**
     * @dev Calculates the discounted price for a bulk purchase
     * @param items Array of item identifiers
     * @param amounts Array of corresponding amounts for each item
     * @param accountId The account making the bulk purchase
     * @return totalDiscountedAmount The total discounted amount for the bulk purchase
     */
    function calculateBulkDiscount(bytes32[] memory items, uint256[] memory amounts, bytes32 accountId) external view returns (uint256 totalDiscountedAmount) {
        require(items.length == amounts.length, "Items and amounts arrays must have the same length");
        require(accountId != bytes32(0), "Invalid account ID");

        uint256 totalOriginalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "All amounts must be greater than zero");
            totalOriginalAmount = totalOriginalAmount.add(amounts[i]);
        }

        uint256 purchaseCount = purchaseCounts[accountId];
        uint256 discountRate = customDiscountRates[accountId] > 0 ? customDiscountRates[accountId] : getCurrentDiscountRate(accountId);

        uint256 discountAmount = totalOriginalAmount.mul(discountRate).div(100);
        totalDiscountedAmount = totalOriginalAmount.sub(discountAmount);

        // Apply additional bulk purchase discount
        if (items.length >= 10) {
            uint256 bulkDiscountRate = 5; // 5% additional discount for 10+ items
            uint256 bulkDiscountAmount = totalDiscountedAmount.mul(bulkDiscountRate).div(100);
            totalDiscountedAmount = totalDiscountedAmount.sub(bulkDiscountAmount);
        }

        return totalDiscountedAmount;
    }

    /**
     * @dev Executes a bulk purchase with discounts applied
     * @param sendAccountId Account making the purchase
     * @param items Array of item identifiers
     * @param amounts Array of corresponding amounts for each item
     * @return success True if the bulk purchase was successful
     */
    function executeBulkPurchase(bytes32 sendAccountId, bytes32[] memory items, uint256[] memory amounts) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(items.length == amounts.length, "Items and amounts arrays must have the same length");
        require(items.length > 0, "At least one item must be purchased");

        uint256 totalDiscountedAmount = calculateBulkDiscount(items, amounts, sendAccountId);

        // Perform the transfer using the token contract
        bool transferResult = token.customTransfer(
            sendAccountId,
            sendAccountId,
            treasuryAccount,
            totalDiscountedAmount,
            keccak256(abi.encodePacked("BULK_PURCHASE", block.timestamp)),
            bytes32(0),
            "Bulk discounted purchase",
            keccak256(abi.encodePacked(sendAccountId, "BULK", block.timestamp))
        );

        require(transferResult, "Bulk transfer failed");

        // Increment the purchase count for the account
        purchaseCounts[sendAccountId] = purchaseCounts[sendAccountId].add(items.length);

        // Emit events for each item in the bulk purchase
        for (uint256 i = 0; i < items.length; i++) {
            emit Discount(sendAccountId, items[i], amounts[i], amounts[i].mul(totalDiscountedAmount).div(calculateBulkDiscount(items, amounts, sendAccountId)));
        }

        return true;
    }

    /**
     * @dev Allows admin to set a time-limited promotional discount
     * @param startTime The start time of the promotion
     * @param endTime The end time of the promotion
     * @param discountRate The promotional discount rate as a percentage
     */
    function setPromotionalDiscount(uint256 startTime, uint256 endTime, uint256 discountRate) external onlyAdmin {
        require(startTime < endTime, "Start time must be before end time");
        require(startTime > block.timestamp, "Start time must be in the future");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");

        promotionalDiscount = PromotionalDiscount({
            startTime: startTime,
            endTime: endTime,
            discountRate: discountRate,
            isActive: true
        });

        emit PromotionalDiscountSet(startTime, endTime, discountRate);
    }

    /**
     * @dev Cancels the current promotional discount
     */
    function cancelPromotionalDiscount() external onlyAdmin {
        require(promotionalDiscount.isActive, "No active promotional discount");

        promotionalDiscount.isActive = false;
        emit PromotionalDiscountCancelled();
    }

    /**
     * @dev Checks if a promotional discount is currently active
     * @return isActive True if a promotional discount is active
     * @return discountRate The current promotional discount rate (0 if not active)
     */
    function checkPromotionalDiscount() external view returns (bool isActive, uint256 discountRate) {
        if (promotionalDiscount.isActive &&
            block.timestamp >= promotionalDiscount.startTime &&
            block.timestamp <= promotionalDiscount.endTime) {
            return (true, promotionalDiscount.discountRate);
        }
        return (false, 0);
    }

    /**
     * @dev Applies the best available discount (regular or promotional) to a purchase
     * @param amount Original purchase amount
     * @param accountId The account making the purchase
     * @return discountedAmount The final discounted amount
     */
    function applyBestDiscount(uint256 amount, bytes32 accountId) external view returns (uint256 discountedAmount) {
        require(amount > 0, "Amount must be greater than zero");
        require(accountId != bytes32(0), "Invalid account ID");

        uint256 regularDiscountRate = getCurrentDiscountRate(accountId);
        (bool isPromoActive, uint256 promoDiscountRate) = checkPromotionalDiscount();

        uint256 bestDiscountRate = regularDiscountRate;
        if (isPromoActive && promoDiscountRate > regularDiscountRate) {
            bestDiscountRate = promoDiscountRate;
        }

        uint256 discountAmount = amount.mul(bestDiscountRate).div(100);
        discountedAmount = amount.sub(discountAmount);

        return discountedAmount;
    }

    /**
     * @dev Retrieves purchase history for an account
     * @param accountId The account to retrieve history for
     * @return purchaseCount The total number of purchases
     * @return totalSpent The total amount spent (before discounts)
     * @return totalSaved The total amount saved through discounts
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 purchaseCount, uint256 totalSpent, uint256 totalSaved) {
        require(accountId != bytes32(0), "Invalid account ID");

        purchaseCount = purchaseCounts[accountId];
        totalSpent = purchaseAmounts[accountId];
        totalSaved = purchaseSavings[accountId];

        return (purchaseCount, totalSpent, totalSaved);
    }

    /**
     * @dev Updates purchase history after a successful purchase
     * @param accountId The account that made the purchase
     * @param originalAmount The original amount before discount
     * @param discountedAmount The final amount after discount
     */
    function updatePurchaseHistory(bytes32 accountId, uint256 originalAmount, uint256 discountedAmount) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
        purchaseAmounts[accountId] = purchaseAmounts[accountId].add(originalAmount);
        purchaseSavings[accountId] = purchaseSavings[accountId].add(originalAmount.sub(discountedAmount));
    }

    /**
     * @dev Allows admin to set a referral bonus discount
     * @param referralDiscountRate The discount rate for the referrer as a percentage
     * @param referredDiscountRate The discount rate for the referred account as a percentage
     */
    function setReferralBonus(uint256 referralDiscountRate, uint256 referredDiscountRate) external onlyAdmin {
        require(referralDiscountRate <= 100, "Referral discount rate cannot exceed 100%");
        require(referredDiscountRate <= 100, "Referred discount rate cannot exceed 100%");

        referralBonus = ReferralBonus({
            referralDiscountRate: referralDiscountRate,
            referredDiscountRate: referredDiscountRate,
            isActive: true
        });

        emit ReferralBonusSet(referralDiscountRate, referredDiscountRate);
    }

    /**
     * @dev Applies a referral bonus to a purchase
     * @param referrerAccountId The account that referred the new customer
     * @param newAccountId The new account making a purchase
     * @param amount The purchase amount
     * @return discountedAmount The final discounted amount after referral bonus
     */
    function applyReferralBonus(bytes32 referrerAccountId, bytes32 newAccountId, uint256 amount) external returns (uint256 discountedAmount) {
        require(referrerAccountId != bytes32(0) && newAccountId != bytes32(0), "Invalid account IDs");
        require(amount > 0, "Amount must be greater than zero");
        require(referralBonus.isActive, "Referral bonus program is not active");
        require(purchaseCounts[newAccountId] == 0, "New account has already made purchases");

        uint256 referredDiscount = amount.mul(referralBonus.referredDiscountRate).div(100);
        discountedAmount = amount.sub(referredDiscount);

        // Apply the discount for the new account
        bool transferResult = token.customTransfer(
            newAccountId,
            newAccountId,
            treasuryAccount,
            discountedAmount,
            keccak256(abi.encodePacked("REFERRAL_PURCHASE", block.timestamp)),
            bytes32(0),
            "Referral bonus purchase",
            keccak256(abi.encodePacked(newAccountId, "REFERRAL", block.timestamp))
        );

        require(transferResult, "Referral purchase transfer failed");

        // Update purchase history for the new account
        updatePurchaseHistory(newAccountId, amount, discountedAmount);

        // Apply bonus discount for the referrer
        uint256 referrerBonus = amount.mul(referralBonus.referralDiscountRate).div(100);
        bool bonusTransfer = token.customTransfer(
            treasuryAccount,
            treasuryAccount,
            referrerAccountId,
            referrerBonus,
            keccak256(abi.encodePacked("REFERRAL_BONUS", block.timestamp)),
            bytes32(0),
            "Referral bonus reward",
            keccak256(abi.encodePacked(referrerAccountId, "BONUS", block.timestamp))
        );

        require(bonusTransfer, "Referral bonus transfer failed");

        emit ReferralBonusApplied(referrerAccount

Here is PART 3 of the smart contract implementation:

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
        
        uint256 discountRate;
        if (purchasedCounts == 0) {
            discountRate = 0; // No discount for first purchase
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
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description
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
            bytes32(0),
            bytes32(0),
            memo,
            traceId
        );
        
        require(result, "Transfer failed");
        
        emit Discount(sendAccountId, item, amount, discountedAmount);
        
        return result;
    }

    /**
     * @dev Retrieves the current discount rate from the oracle
     * @return discountRate Current discount rate as a percentage
     */
    function _getCurrentDiscountRate() internal view returns (uint256 discountRate) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to retrieve discount rate");
        discountRate = uint256(value);
        require(discountRate <= 100, "Invalid discount rate");
        return discountRate;
    }

    /**
     * @dev Applies a dynamic discount based on the current oracle rate
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying the current discount rate
     */
    function _applyDynamicDiscount(uint256 amount) internal view returns (uint256 discountedAmount) {
        uint256 discountRate = _getCurrentDiscountRate();
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Checks if an account is eligible for a special promotion
     * @param accountId Account to check for promotion eligibility
     * @return isEligible True if the account is eligible for a promotion
     */
    function _isEligibleForPromotion(bytes32 accountId) internal view returns (bool isEligible) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("PROMO_", accountId)));
        require(bytes(err).length == 0, "Failed to check promotion eligibility");
        return value != bytes32(0);
    }

    /**
     * @dev Applies a promotional discount if the account is eligible
     * @param accountId Account to apply the promotion to
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying any applicable promotion
     */
    function _applyPromotionalDiscount(bytes32 accountId, uint256 amount) internal returns (uint256 discountedAmount) {
        if (_isEligibleForPromotion(accountId)) {
            uint256 promoDiscount = amount.mul(25).div(100); // 25% promotional discount
            discountedAmount = amount.sub(promoDiscount);
            
            // Mark promotion as used
            oracle.set(oracleId, keccak256(abi.encodePacked("PROMO_", accountId)), bytes32(0));
            
            emit Discount(accountId, "PROMO", amount, discountedAmount);
        } else {
            discountedAmount = amount;
        }
        return discountedAmount;
    }

    /**
     * @dev Calculates loyalty points based on purchase amount
     * @param amount Purchase amount
     * @return points Loyalty points earned
     */
    function _calculateLoyaltyPoints(uint256 amount) internal pure returns (uint256 points) {
        return amount.div(100); // 1 point per 100 units spent
    }

    /**
     * @dev Awards loyalty points to an account
     * @param accountId Account to award points to
     * @param amount Purchase amount
     */
    function _awardLoyaltyPoints(bytes32 accountId, uint256 amount) internal {
        uint256 points = _calculateLoyaltyPoints(amount);
        bytes32 pointsKey = keccak256(abi.encodePacked("LOYALTY_POINTS_", accountId));
        
        (bytes32 currentPointsValue, string memory err) = oracle.get(oracleId, pointsKey);
        require(bytes(err).length == 0, "Failed to retrieve current loyalty points");
        
        uint256 currentPoints = uint256(currentPointsValue);
        uint256 newPoints = currentPoints.add(points);
        
        oracle.set(oracleId, pointsKey, bytes32(newPoints));
    }

    /**
     * @dev Checks if an account has sufficient loyalty points for redemption
     * @param accountId Account to check
     * @param requiredPoints Number of points required
     * @return hasEnoughPoints True if the account has sufficient points
     */
    function _hasEnoughLoyaltyPoints(bytes32 accountId, uint256 requiredPoints) internal view returns (bool hasEnoughPoints) {
        bytes32 pointsKey = keccak256(abi.encodePacked("LOYALTY_POINTS_", accountId));
        (bytes32 pointsValue, string memory err) = oracle.get(oracleId, pointsKey);
        require(bytes(err).length == 0, "Failed to retrieve loyalty points");
        
        uint256 currentPoints = uint256(pointsValue);
        return currentPoints >= requiredPoints;
    }

    /**
     * @dev Redeems loyalty points for a discount
     * @param accountId Account redeeming points
     * @param pointsToRedeem Number of points to redeem
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying loyalty discount
     */
    function _redeemLoyaltyPoints(bytes32 accountId, uint256 pointsToRedeem, uint256 amount) internal returns (uint256 discountedAmount) {
        require(_hasEnoughLoyaltyPoints(accountId, pointsToRedeem), "Insufficient loyalty points");
        
        uint256 discountPerPoint = 1; // 1 unit of discount per point
        uint256 loyaltyDiscount = pointsToRedeem.mul(discountPerPoint);
        discountedAmount = amount > loyaltyDiscount ? amount.sub(loyaltyDiscount) : 0;
        
        // Deduct redeemed points
        bytes32 pointsKey = keccak256(abi.encodePacked("LOYALTY_POINTS_", accountId));
        (bytes32 currentPointsValue, string memory err) = oracle.get(oracleId, pointsKey);
        require(bytes(err).length == 0, "Failed to retrieve current loyalty points");
        
        uint256 currentPoints = uint256(currentPointsValue);
        uint256 remainingPoints = currentPoints.sub(pointsToRedeem);
        
        oracle.set(oracleId, pointsKey, bytes32(remainingPoints));
        
        emit Discount(accountId, "LOYALTY", amount, discountedAmount);
        
        return discountedAmount;
    }

    /**
     * @dev Checks if a bulk discount should be applied based on purchase amount
     * @param amount Purchase amount
     * @return shouldApply True if bulk discount should be applied
     * @return discountRate Discount rate to apply
     */
    function _checkBulkDiscount(uint256 amount) internal pure returns (bool shouldApply, uint256 discountRate) {
        if (amount >= 10000) {
            return (true, 15); // 15% discount for purchases of 10000 or more
        } else if (amount >= 5000) {
            return (true, 10); // 10% discount for purchases between 5000 and 9999
        } else if (amount >= 1000) {
            return (true, 5); // 5% discount for purchases between 1000 and 4999
        } else {
            return (false, 0);
        }
    }

    /**
     * @dev Applies a bulk discount if applicable
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying any bulk discount
     */
    function _applyBulkDiscount(uint256 amount) internal pure returns (uint256 discountedAmount) {
        (bool shouldApply, uint256 discountRate) = _checkBulkDiscount(amount);
        
        if (shouldApply) {
            uint256 discountAmount = amount.mul(discountRate).div(100);
            discountedAmount = amount.sub(discountAmount);
        } else {
            discountedAmount = amount;
        }
        
        return discountedAmount;
    }

    /**
     * @dev Checks if a seasonal discount is currently active
     * @return isActive True if a seasonal discount is active
     * @return discountRate Current seasonal discount rate
     */
    function _checkSeasonalDiscount() internal view returns (bool isActive, uint256 discountRate) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "SEASONAL_DISCOUNT");
        require(bytes(err).length == 0, "Failed to check seasonal discount");
        
        if (value != bytes32(0)) {
            isActive = true;
            discountRate = uint256(value);
            require(discountRate <= 100, "Invalid seasonal discount rate");
        } else {
            isActive = false;
            discountRate = 0;
        }
        
        return (isActive, discountRate);
    }

    /**
     * @dev Applies a seasonal discount if active
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying any seasonal discount
     */
    function _applySeasonalDiscount(uint256 amount) internal view returns (uint256 discountedAmount) {
        (bool isActive, uint256 discountRate) = _checkSeasonalDiscount();
        
        if (isActive) {
            uint256 discountAmount = amount.mul(discountRate).div(100);
            discountedAmount = amount.sub(discountAmount);
        } else {
            discountedAmount = amount;
        }
        
        return discountedAmount;
    }

    /**
     * @dev Checks if a referral discount should be applied
     * @param accountId Account to check for referral eligibility
     * @return isEligible True if the account is eligible for a referral discount
     * @return referrerAccountId Account ID of the referrer, if applicable
     */
    function _checkReferralDiscount(bytes32 accountId) internal view returns (bool isEligible, bytes32 referrerAccountId) {
        bytes32 referralKey = keccak256(abi.encodePacked("REFERRAL_", accountId));
        (bytes32 value, string memory err) = oracle.get(oracleId, referralKey);
        require(bytes(err).length == 0, "Failed to check referral status");
        
        if (value != bytes32(0)) {
            isEligible = true;
            referrerAccountId = value;
        } else {
            isEligible = false;
            referrerAccountId = bytes32(0);
        }
        
        return (isEligible, referrerAccountId);
    }

    /**
     * @dev Applies a referral discount and rewards the referrer
     * @param accountId Account making the purchase
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying referral discount
     */
    function _applyReferralDiscount(bytes32 accountId, uint256 amount) internal returns (uint256 discountedAmount) {
        (bool isEligible, bytes32 referrerAccountId) = _checkReferralDiscount(accountId);
        
        if (isEligible) {
            uint256 discountRate = 10; // 10% discount for referred customers
            uint256 discountAmount = amount.mul(discountRate).div(100);
            discountedAmount = amount.sub(discountAmount);
            
            // Reward referrer
            uint256 referrerReward = discountAmount.div(2); // 50% of the discount as reward
            _awardReferrerBonus(referrerAccountId, referrerReward);
            
            // Mark referral as used
            oracle.set(oracleId, keccak256(abi.encodePacked("REFERRAL_", accountId)), bytes32(0));
            
            emit Discount(accountId, "REFERRAL", amount, discountedAmount);
        } else {
            discountedAmount = amount;
        }
        
        return discountedAmount;
    }

    /**
     * @dev Awards a bonus to the referrer
     * @param referrerAccountId Account ID of the referrer
     * @param rewardAmount Amount of reward to give to the referrer
     */
    function _awardReferrerBonus(bytes32 referrerAccountId, uint256 rewardAmount) internal {
        bytes32 bonusKey = keccak256(abi.encodePacked("REFERRER_BONUS_", referrerAccountId));
        (bytes32 currentBonusValue, string memory err) = oracle.get(oracleId, bonusKey);
        require(bytes(err).length == 0, "Failed to retrieve current referrer bonus");
        
        uint256 currentBonus = uint256(currentBonusValue);
        uint256 newBonus = currentBonus.add(rewardAmount);
        
        oracle.set(oracleId, bonusKey, bytes32(newBonus));
    }

    /**
     * @dev Checks if a bundle discount should be applied based on items purchased
     * @param items Array of item identifiers in the purchase
     * @return shouldApply True if a bundle discount should be applied
     * @return discountRate Discount rate to apply for the bundle
     */
    function _checkBundleDiscount(bytes32[] memory items) internal view returns (bool shouldApply, uint256 discountRate) {
        bytes32 bundleKey = keccak256(abi.encodePacked(items));
        (bytes32 value, string memory err) = oracle.get(oracleId, bundleKey);