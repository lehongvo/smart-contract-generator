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
    event PurchaseCountUpdated(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyAuthorizedInvoker() {
        require(oracle.isAuthorizedInvoker(msg.sender, oracleId), "Caller is not authorized");
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    /**
     * @dev Constructor to set the owner
     */
    constructor() Ownable() {
        // Intentionally left empty
    }

    // END PART 1

Here's PART 2 of the smart contract implementation for the Discount contract:

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
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchaseHistory Number of previous purchases by the account
     * @param memo Description of the purchase
     * @param traceId Unique identifier for this transaction
     * @return success True if the discounted purchase was successful
     */
    function applyDiscountAndPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchaseHistory,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid send account");
        require(fromAccountId != bytes32(0), "Invalid from account");
        require(toAccountId != bytes32(0), "Invalid to account");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        uint256 discountedAmount = discount(amount, purchaseHistory);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(purchaseHistory),
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Retrieves the current discount rate from the oracle
     * @return discountRate The current discount rate as a percentage
     */
    function getCurrentDiscountRate() public view returns (uint256 discountRate) {
        (bytes32 rateValue, string memory err) = oracle.get(currentOracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Error fetching discount rate");
        return uint256(rateValue);
    }

    /**
     * @dev Updates the discount rate in the oracle
     * @param newRate New discount rate to set (as a percentage)
     * @notice Only callable by contract owner
     */
    function updateDiscountRate(uint256 newRate) external onlyOwner {
        require(newRate <= 100, "Discount rate cannot exceed 100%");
        oracle.set(currentOracleId, "DISCOUNT_RATE", bytes32(newRate));
        emit DiscountRateUpdated(newRate);
    }

    /**
     * @dev Applies a special promotional discount
     * @param accountId Account to receive the promotion
     * @param promotionCode Unique code for the promotion
     * @return discountPercentage The applied discount percentage
     */
    function applyPromotion(bytes32 accountId, bytes32 promotionCode) external returns (uint256 discountPercentage) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(promotionCode != bytes32(0), "Invalid promotion code");

        // Check if the promotion code is valid
        bool isValid = checkPromotionValidity(promotionCode);
        require(isValid, "Invalid or expired promotion code");

        // Get the discount percentage for this promotion
        discountPercentage = getPromotionDiscount(promotionCode);

        // Record the use of the promotion code
        recordPromotionUsage(accountId, promotionCode);

        emit PromotionApplied(accountId, promotionCode, discountPercentage);

        return discountPercentage;
    }

    /**
     * @dev Checks if a promotion code is valid
     * @param promotionCode Code to validate
     * @return isValid True if the code is valid and not expired
     */
    function checkPromotionValidity(bytes32 promotionCode) internal view returns (bool isValid) {
        // Implementation would typically involve checking against a stored list of valid codes
        // and their expiration dates. This is a simplified example.
        (bytes32 validUntil, string memory err) = oracle.get(currentOracleId, promotionCode);
        if (bytes(err).length > 0 || validUntil == bytes32(0)) {
            return false;
        }
        return block.timestamp <= uint256(validUntil);
    }

    /**
     * @dev Retrieves the discount percentage for a given promotion
     * @param promotionCode Promotion code to check
     * @return discount Discount percentage for the promotion
     */
    function getPromotionDiscount(bytes32 promotionCode) internal view returns (uint256 discount) {
        (bytes32 discountValue, string memory err) = oracle.get(currentOracleId, keccak256(abi.encodePacked("PROMO_DISCOUNT_", promotionCode)));
        require(bytes(err).length == 0, "Error fetching promotion discount");
        return uint256(discountValue);
    }

    /**
     * @dev Records the usage of a promotion code by an account
     * @param accountId Account using the promotion
     * @param promotionCode Code being used
     */
    function recordPromotionUsage(bytes32 accountId, bytes32 promotionCode) internal {
        // Implementation would typically involve updating a mapping or other data structure
        // to track which accounts have used which promotion codes.
        // This is a placeholder for that logic.
        emit PromotionUsed(accountId, promotionCode);
    }

    /**
     * @dev Calculates a loyalty bonus based on account history
     * @param accountId Account to calculate bonus for
     * @return bonusPercentage Loyalty bonus as a percentage
     */
    function calculateLoyaltyBonus(bytes32 accountId) public view returns (uint256 bonusPercentage) {
        require(accountId != bytes32(0), "Invalid account ID");

        // Fetch account history from oracle or internal state
        uint256 accountAge = getAccountAge(accountId);
        uint256 totalPurchases = getTotalPurchases(accountId);

        // Calculate bonus based on account age and purchase history
        if (accountAge >= 365 days && totalPurchases >= 100) {
            bonusPercentage = 5; // 5% bonus for loyal customers
        } else if (accountAge >= 180 days && totalPurchases >= 50) {
            bonusPercentage = 3; // 3% bonus for regular customers
        } else if (accountAge >= 30 days && totalPurchases >= 10) {
            bonusPercentage = 1; // 1% bonus for new regular customers
        } else {
            bonusPercentage = 0; // No bonus for new or infrequent customers
        }

        return bonusPercentage;
    }

    /**
     * @dev Retrieves the age of an account
     * @param accountId Account to check
     * @return age Age of the account in seconds
     */
    function getAccountAge(bytes32 accountId) internal view returns (uint256 age) {
        (bytes32 creationTime, string memory err) = oracle.get(currentOracleId, keccak256(abi.encodePacked("ACCOUNT_CREATION_", accountId)));
        require(bytes(err).length == 0, "Error fetching account creation time");
        return block.timestamp - uint256(creationTime);
    }

    /**
     * @dev Retrieves the total number of purchases for an account
     * @param accountId Account to check
     * @return purchases Total number of purchases
     */
    function getTotalPurchases(bytes32 accountId) internal view returns (uint256 purchases) {
        (bytes32 purchaseCount, string memory err) = oracle.get(currentOracleId, keccak256(abi.encodePacked("TOTAL_PURCHASES_", accountId)));
        require(bytes(err).length == 0, "Error fetching total purchases");
        return uint256(purchaseCount);
    }

    /**
     * @dev Applies a loyalty bonus to a purchase
     * @param accountId Account making the purchase
     * @param amount Original purchase amount
     * @return bonusAmount Additional bonus amount awarded
     */
    function applyLoyaltyBonus(bytes32 accountId, uint256 amount) external returns (uint256 bonusAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than zero");

        uint256 bonusPercentage = calculateLoyaltyBonus(accountId);
        bonusAmount = amount.mul(bonusPercentage).div(100);

        // Apply the bonus (e.g., add to account balance or provide as cashback)
        applyBonus(accountId, bonusAmount);

        emit LoyaltyBonusApplied(accountId, amount, bonusAmount);

        return bonusAmount;
    }

    /**
     * @dev Internal function to apply a bonus to an account
     * @param accountId Account receiving the bonus
     * @param bonusAmount Amount of bonus to apply
     */
    function applyBonus(bytes32 accountId, uint256 bonusAmount) internal {
        // Implementation would typically involve updating the account's balance
        // or creating a separate bonus balance. This is a placeholder for that logic.
        emit BonusApplied(accountId, bonusAmount);
    }

    /**
     * @dev Calculates a tiered discount based on purchase amount
     * @param amount Purchase amount
     * @return discountPercentage Discount percentage to apply
     */
    function calculateTieredDiscount(uint256 amount) public pure returns (uint256 discountPercentage) {
        if (amount >= 10000 ether) {
            return 15; // 15% discount for purchases of 10000 ETH or more
        } else if (amount >= 5000 ether) {
            return 10; // 10% discount for purchases between 5000 and 9999.99 ETH
        } else if (amount >= 1000 ether) {
            return 5; // 5% discount for purchases between 1000 and 4999.99 ETH
        } else {
            return 0; // No discount for purchases under 1000 ETH
        }
    }

    /**
     * @dev Applies a tiered discount to a purchase
     * @param accountId Account making the purchase
     * @param amount Purchase amount
     * @return discountedAmount Final amount after applying tiered discount
     */
    function applyTieredDiscount(bytes32 accountId, uint256 amount) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage = calculateTieredDiscount(amount);
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        discountedAmount = amount.sub(discountAmount);

        emit TieredDiscountApplied(accountId, amount, discountedAmount, discountPercentage);

        return discountedAmount;
    }

    /**
     * @dev Checks if an account is eligible for a special discount
     * @param accountId Account to check
     * @return isEligible True if the account is eligible for a special discount
     */
    function isEligibleForSpecialDiscount(bytes32 accountId) public view returns (bool isEligible) {
        require(accountId != bytes32(0), "Invalid account ID");

        // Check various conditions for special discount eligibility
        uint256 accountAge = getAccountAge(accountId);
        uint256 totalPurchases = getTotalPurchases(accountId);
        uint256 lastPurchaseTime = getLastPurchaseTime(accountId);

        // Example eligibility criteria:
        // 1. Account is at least 1 year old
        // 2. Has made at least 50 purchases
        // 3. Last purchase was within the last 30 days
        if (accountAge >= 365 days && totalPurchases >= 50 && (block.timestamp - lastPurchaseTime) <= 30 days) {
            return true;
        }

        return false;
    }

    /**
     * @dev Retrieves the timestamp of the last purchase for an account
     * @param accountId Account to check
     * @return lastPurchaseTime Timestamp of the last purchase
     */
    function getLastPurchaseTime(bytes32 accountId) internal view returns (uint256 lastPurchaseTime) {
        (bytes32 purchaseTime, string memory err) = oracle.get(currentOracleId, keccak256(abi.encodePacked("LAST_PURCHASE_TIME_", accountId)));
        require(bytes(err).length == 0, "Error fetching last purchase time");
        return uint256(purchaseTime);
    }

    /**
     * @dev Applies a special discount if the account is eligible
     * @param accountId Account to apply the discount to
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying special discount
     */
    function applySpecialDiscount(bytes32 accountId, uint256 amount) external returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than zero");

        if (isEligibleForSpecialDiscount(accountId)) {
            uint256 specialDiscountPercentage = 25; // 25% special discount
            uint256 discountAmount = amount.mul(specialDiscountPercentage).div(100);
            discountedAmount = amount.sub(discountAmount);

            emit SpecialDiscountApplied(accountId, amount, discountedAmount, specialDiscountPercentage);
        } else {
            discountedAmount = amount;
        }

        return discountedAmount;
    }

    /**
     * @dev Calculates a cumulative discount based on multiple factors
     * @param accountId Account making the purchase
     * @param amount Original purchase amount
     * @return finalAmount Final amount after applying all applicable discounts
     */
    function calculateCumulativeDiscount(bytes32 accountId, uint256 amount) public view returns (uint256 finalAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than zero");

        uint256 remainingAmount = amount;

        // Apply tiered discount
        uint256 tieredDiscountPercentage = calculateTieredDiscount(amount);
        remainingAmount

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
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description
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
     * @dev Retrieves the current discount rate from the oracle
     * @return uint256 Current discount rate as a percentage
     */
    function _getCurrentDiscountRate() internal view returns (uint256) {
        (bytes32 rateBytes, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to retrieve discount rate");
        return uint256(rateBytes);
    }

    /**
     * @dev Updates the purchase history for an account
     * @param accountId The account to update
     */
    function _updatePurchaseHistory(bytes32 accountId) internal {
        purchaseHistory[accountId] = purchaseHistory[accountId].add(1);
    }

    /**
     * @dev Checks if an account is eligible for a discount
     * @param accountId The account to check
     * @return bool True if the account is eligible for a discount
     */
    function _isEligibleForDiscount(bytes32 accountId) internal view returns (bool) {
        return !blacklistedAccounts[accountId] && purchaseHistory[accountId] > 0;
    }

    /**
     * @dev Applies a special promotion discount if applicable
     * @param amount The original amount
     * @return uint256 The amount after applying any promotional discounts
     */
    function _applyPromotionalDiscount(uint256 amount) internal view returns (uint256) {
        if (block.timestamp < promotionEndTime) {
            uint256 promotionalRate = _getCurrentPromotionalRate();
            return amount.mul(100 - promotionalRate).div(100);
        }
        return amount;
    }

    /**
     * @dev Retrieves the current promotional discount rate
     * @return uint256 The promotional discount rate as a percentage
     */
    function _getCurrentPromotionalRate() internal view returns (uint256) {
        (bytes32 rateBytes, string memory err) = oracle.get(oracleId, "PROMO_RATE");
        require(bytes(err).length == 0, "Failed to retrieve promotional rate");
        return uint256(rateBytes);
    }

    /**
     * @dev Checks if a purchase qualifies for bulk discount
     * @param amount The purchase amount
     * @return bool True if the purchase qualifies for bulk discount
     */
    function _qualifiesForBulkDiscount(uint256 amount) internal view returns (bool) {
        return amount >= bulkDiscountThreshold;
    }

    /**
     * @dev Applies bulk discount if applicable
     * @param amount The original amount
     * @return uint256 The amount after applying bulk discount if applicable
     */
    function _applyBulkDiscount(uint256 amount) internal view returns (uint256) {
        if (_qualifiesForBulkDiscount(amount)) {
            return amount.mul(100 - bulkDiscountRate).div(100);
        }
        return amount;
    }

    /**
     * @dev Calculates loyalty points for a purchase
     * @param amount The purchase amount
     * @return uint256 The number of loyalty points earned
     */
    function _calculateLoyaltyPoints(uint256 amount) internal pure returns (uint256) {
        return amount.div(100); // 1 point per 100 units spent
    }

    /**
     * @dev Awards loyalty points to an account
     * @param accountId The account to award points to
     * @param amount The purchase amount
     */
    function _awardLoyaltyPoints(bytes32 accountId, uint256 amount) internal {
        uint256 points = _calculateLoyaltyPoints(amount);
        loyaltyPoints[accountId] = loyaltyPoints[accountId].add(points);
        emit LoyaltyPointsAwarded(accountId, points);
    }

    /**
     * @dev Checks if an account has enough loyalty points for redemption
     * @param accountId The account to check
     * @return bool True if the account has enough points for redemption
     */
    function _hasEnoughLoyaltyPoints(bytes32 accountId) internal view returns (bool) {
        return loyaltyPoints[accountId] >= loyaltyPointsThreshold;
    }

    /**
     * @dev Redeems loyalty points for a discount
     * @param accountId The account redeeming points
     * @param amount The original purchase amount
     * @return uint256 The discounted amount after loyalty point redemption
     */
    function _redeemLoyaltyPoints(bytes32 accountId, uint256 amount) internal returns (uint256) {
        if (_hasEnoughLoyaltyPoints(accountId)) {
            uint256 pointsToRedeem = loyaltyPointsThreshold;
            loyaltyPoints[accountId] = loyaltyPoints[accountId].sub(pointsToRedeem);
            uint256 discountAmount = pointsToRedeem.mul(loyaltyPointValue);
            emit LoyaltyPointsRedeemed(accountId, pointsToRedeem);
            return amount > discountAmount ? amount.sub(discountAmount) : 0;
        }
        return amount;
    }

    /**
     * @dev Checks if a referral bonus should be applied
     * @param accountId The account to check
     * @return bool True if the account is eligible for a referral bonus
     */
    function _isEligibleForReferralBonus(bytes32 accountId) internal view returns (bool) {
        return referrals[accountId] != bytes32(0) && !referralBonusApplied[accountId];
    }

    /**
     * @dev Applies a referral bonus discount
     * @param amount The original amount
     * @return uint256 The amount after applying the referral bonus discount
     */
    function _applyReferralBonus(uint256 amount) internal view returns (uint256) {
        return amount.mul(100 - referralBonusRate).div(100);
    }

    /**
     * @dev Marks a referral bonus as applied for an account
     * @param accountId The account that used the referral bonus
     */
    function _markReferralBonusApplied(bytes32 accountId) internal {
        referralBonusApplied[accountId] = true;
        emit ReferralBonusApplied(accountId, referrals[accountId]);
    }

    /**
     * @dev Checks if a purchase is eligible for a seasonal discount
     * @return bool True if the current time falls within a seasonal discount period
     */
    function _isSeasonalDiscountActive() internal view returns (bool) {
        uint256 currentTimestamp = block.timestamp;
        return currentTimestamp >= seasonalDiscountStart && currentTimestamp <= seasonalDiscountEnd;
    }

    /**
     * @dev Applies a seasonal discount if active
     * @param amount The original amount
     * @return uint256 The amount after applying any seasonal discount
     */
    function _applySeasonalDiscount(uint256 amount) internal view returns (uint256) {
        if (_isSeasonalDiscountActive()) {
            return amount.mul(100 - seasonalDiscountRate).div(100);
        }
        return amount;
    }

    /**
     * @dev Calculates the final discounted amount considering all discount types
     * @param sendAccountId The account making the purchase
     * @param amount The original purchase amount
     * @return uint256 The final discounted amount
     */
    function calculateFinalDiscount(bytes32 sendAccountId, uint256 amount) public view returns (uint256) {
        uint256 discountedAmount = amount;

        // Apply base discount
        discountedAmount = discount(discountedAmount, purchaseHistory[sendAccountId]);

        // Apply promotional discount
        discountedAmount = _applyPromotionalDiscount(discountedAmount);

        // Apply bulk discount
        discountedAmount = _applyBulkDiscount(discountedAmount);

        // Apply seasonal discount
        discountedAmount = _applySeasonalDiscount(discountedAmount);

        // Apply referral bonus if eligible
        if (_isEligibleForReferralBonus(sendAccountId)) {
            discountedAmount = _applyReferralBonus(discountedAmount);
        }

        // Apply loyalty point redemption
        if (_hasEnoughLoyaltyPoints(sendAccountId)) {
            discountedAmount = _redeemLoyaltyPoints(sendAccountId, discountedAmount);
        }

        return discountedAmount;
    }

    /**
     * @dev Executes a purchase with all applicable discounts
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Human readable transfer description
     * @param traceId Unique identifier for tracking this transaction
     * @return bool True if the discounted purchase was successful
     */
    function executePurchaseWithDiscount(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) external returns (bool) {
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
            _updatePurchaseHistory(sendAccountId);
            _awardLoyaltyPoints(sendAccountId, finalAmount);

            if (_isEligibleForReferralBonus(sendAccountId)) {
                _markReferralBonusApplied(sendAccountId);
            }
        }

        return transferResult;
    }

    /**
     * @dev Sets the bulk discount threshold and rate
     * @param threshold The minimum amount for bulk discount
     * @param rate The discount rate for bulk purchases
     * @notice Only admin can call this function
     */
    function setBulkDiscount(uint256 threshold, uint256 rate) external onlyAdmin {
        require(threshold > 0, "Threshold must be greater than zero");
        require(rate <= 100, "Rate must be 100 or less");
        bulkDiscountThreshold = threshold;
        bulkDiscountRate = rate;
        emit BulkDiscountUpdated(threshold, rate);
    }

    /**
     * @dev Sets the loyalty points threshold and value
     * @param threshold The number of points needed for redemption
     * @param value The value of each loyalty point
     * @notice Only admin can call this function
     */
    function setLoyaltyProgram(uint256 threshold, uint256 value) external onlyAdmin {
        require(threshold > 0, "Threshold must be greater than zero");
        require(value > 0, "Value must be greater than zero");
        loyaltyPointsThreshold = threshold;
        loyaltyPointValue = value;
        emit LoyaltyProgramUpdated(threshold, value);
    }

    /**
     * @dev Sets the referral bonus rate
     * @param rate The discount rate for referral bonuses
     * @notice Only admin can call this function
     */
    function setReferralBonus(uint256 rate) external onlyAdmin {
        require(rate <= 100, "Rate must be 100 or less");
        referralBonusRate = rate;
        emit ReferralBonusUpdated(rate);
    }

    /**
     * @dev Sets the seasonal discount period and rate
     * @param start The start timestamp of the seasonal discount
     * @param end The end timestamp of the seasonal discount
     * @param rate The discount rate for the seasonal period
     * @notice Only admin can call this function
     */
    function setSeasonalDiscount(uint256 start, uint256 end, uint256 rate) external onlyAdmin {
        require(start < end, "Invalid date range");
        require(rate <= 100, "Rate must be 100 or less");
        seasonalDiscountStart = start;
        seasonalDiscountEnd = end;
        seasonalDiscountRate = rate;
        emit SeasonalDiscountUpdated(start, end, rate);
    }

    /**
     * @dev Adds an account to the discount blacklist
     * @param accountId The account to blacklist
     * @notice Only admin can call this function
     */
    function addToBlacklist(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        blacklistedAccounts[accountId] = true;
        emit AccountBlacklisted(accountId);
    }

    /**
     * @dev Removes an account from the discount blacklist
     * @param accountId The account to remove from the blacklist
     * @notice Only admin can call this function
     */
    function removeFromBlacklist(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account ID");
        blacklistedAccounts[accountId] = false;
        emit AccountUnblacklisted(accountId);
    }

    /**