// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Initializable, ReentrancyGuard, Ownable {
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
    uint256 private constant MAX_DISCOUNT = 20; // 20% max discount

    // Events
    event OracleUpdated(uint256 indexed oldOracleId, uint256 indexed newOracleId);
    event PurchaseCountUpdated(bytes32 indexed accountId, uint256 newCount);

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
        require(isActive == bytes32(uint256(1)), "New oracle is not active");
        require(bytes(err).length == 0, "Error checking oracle status");

        uint256 oldOracleId = oracleId;
        oracleId = _oracleId;
        emit OracleUpdated(oldOracleId, _oracleId);
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
    ) external override nonReentrant onlyActiveOracle returns (bool result) {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Check if accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        uint256 balance = getAccountBalance(fromAccountId);
        require(balance >= amount, "Insufficient balance in source account");

        // Apply discount
        uint256 purchaseCount = purchaseCounts[sendAccountId];
        uint256 discountedAmount = this.discount(amount, purchaseCount);

        // Perform transfer
        bool transferSuccess = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            miscValue1,
            miscValue2,
            memo,
            traceId
        );

        require(transferSuccess, "Transfer failed");

        // Update purchase count
        purchaseCounts[sendAccountId] = purchaseCount.add(1);
        emit PurchaseCountUpdated(sendAccountId, purchaseCounts[sendAccountId]);

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
        (bytes32 isActive, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE_", accountId)));
        require(bytes(err).length == 0, "Error checking account status");
        return isActive == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 balance, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE_", accountId)));
        require(bytes(err).length == 0, "Error fetching account balance");
        return uint256(balance);
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
        
        if (purchasedCounts == 0) {
            discountPercentage = 0; // No discount for first-time buyers
        } else if (purchasedCounts < 5) {
            discountPercentage = 5; // 5% discount for 1-4 previous purchases
        } else if (purchasedCounts < 10) {
            discountPercentage = 10; // 10% discount for 5-9 previous purchases
        } else if (purchasedCounts < 20) {
            discountPercentage = 15; // 15% discount for 10-19 previous purchases
        } else {
            discountPercentage = 20; // 20% discount for 20+ previous purchases
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        uint256 finalAmount = amount.sub(discountAmount);

        return finalAmount;
    }

    /**
     * @dev Applies discount to a purchase and executes the transfer
     * @param sendAccountId Account making the purchase
     * @param toAccountId Destination account (e.g., merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by the account
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the discounted purchase was successful
     */
    function discountedPurchase(
        bytes32 sendAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid sender account");
        require(toAccountId != bytes32(0), "Invalid recipient account");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        uint256 discountedAmount = discount(amount, purchasedCounts);

        bool transferResult = customTransfer(
            sendAccountId,
            sendAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(discountedAmount),
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchasedCounts Number of previous purchases by the account
     * @return discountRate The current discount rate as a percentage
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
     * @dev Calculates the potential savings for a purchase
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by the account
     * @return savings The amount saved due to the discount
     */
    function calculateSavings(uint256 amount, uint256 purchasedCounts) external pure returns (uint256 savings) {
        uint256 discountedAmount = discount(amount, purchasedCounts);
        return amount.sub(discountedAmount);
    }

    /**
     * @dev Checks if an account is eligible for a discount
     * @param accountId Account to check for eligibility
     * @return eligible True if the account is eligible for a discount
     */
    function isEligibleForDiscount(bytes32 accountId) external view returns (bool eligible) {
        require(accountId != bytes32(0), "Invalid account ID");
        
        // Implement logic to check if the account is eligible for a discount
        // This could involve checking the account's purchase history, membership status, etc.
        // For this example, we'll assume all accounts with at least one purchase are eligible

        uint256 purchaseCount = getPurchaseCount(accountId);
        return purchaseCount > 0;
    }

    /**
     * @dev Retrieves the purchase count for a given account
     * @param accountId Account to check
     * @return count Number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) internal view returns (uint256 count) {
        // In a real implementation, this would query a storage mapping or external service
        // For this example, we'll return a mock value
        return 5;
    }

    /**
     * @dev Applies a special promotional discount to a purchase
     * @param sendAccountId Account making the purchase
     * @param toAccountId Destination account (e.g., merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param promoCode Promotional code to apply
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the discounted purchase was successful
     */
    function applyPromotionalDiscount(
        bytes32 sendAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        bytes32 promoCode,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid sender account");
        require(toAccountId != bytes32(0), "Invalid recipient account");
        require(amount > 0, "Amount must be greater than zero");
        require(promoCode != bytes32(0), "Invalid promo code");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        uint256 discountedAmount = applyPromoCode(amount, promoCode);

        bool transferResult = customTransfer(
            sendAccountId,
            sendAccountId,
            toAccountId,
            discountedAmount,
            item,
            promoCode,
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Applies a promotional code to calculate the discounted amount
     * @param amount Original purchase amount
     * @param promoCode Promotional code to apply
     * @return discountedAmount The final amount after applying the promotional discount
     */
    function applyPromoCode(uint256 amount, bytes32 promoCode) internal pure returns (uint256 discountedAmount) {
        // In a real implementation, this would query a database of valid promo codes
        // For this example, we'll use a simple hash-based approach

        uint256 discountPercentage;

        if (promoCode == keccak256("SUMMER2023")) {
            discountPercentage = 15; // 15% off for summer promotion
        } else if (promoCode == keccak256("NEWCUSTOMER")) {
            discountPercentage = 20; // 20% off for new customers
        } else if (promoCode == keccak256("FLASH50")) {
            discountPercentage = 50; // 50% off flash sale
        } else {
            discountPercentage = 0; // Invalid or expired promo code
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Checks if a promotional code is valid
     * @param promoCode Promotional code to check
     * @return valid True if the promotional code is valid and active
     */
    function isValidPromoCode(bytes32 promoCode) external pure returns (bool valid) {
        // In a real implementation, this would query a database of valid promo codes
        // For this example, we'll use the same simple hash-based approach as in applyPromoCode

        return (promoCode == keccak256("SUMMER2023") ||
                promoCode == keccak256("NEWCUSTOMER") ||
                promoCode == keccak256("FLASH50"));
    }

    /**
     * @dev Retrieves the discount percentage for a given promotional code
     * @param promoCode Promotional code to check
     * @return percentage The discount percentage for the promotional code (0 if invalid)
     */
    function getPromoCodeDiscount(bytes32 promoCode) external pure returns (uint256 percentage) {
        if (promoCode == keccak256("SUMMER2023")) {
            return 15;
        } else if (promoCode == keccak256("NEWCUSTOMER")) {
            return 20;
        } else if (promoCode == keccak256("FLASH50")) {
            return 50;
        } else {
            return 0;
        }
    }

    /**
     * @dev Applies a tiered discount based on the total purchase amount
     * @param amount Original purchase amount
     * @return discountedAmount The final amount after applying the tiered discount
     */
    function applyTieredDiscount(uint256 amount) external pure returns (uint256 discountedAmount) {
        uint256 discountPercentage;

        if (amount < 100 ether) {
            discountPercentage = 0; // No discount for purchases under 100 tokens
        } else if (amount < 500 ether) {
            discountPercentage = 5; // 5% discount for purchases between 100 and 499 tokens
        } else if (amount < 1000 ether) {
            discountPercentage = 10; // 10% discount for purchases between 500 and 999 tokens
        } else {
            discountPercentage = 15; // 15% discount for purchases of 1000 tokens or more
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Calculates a loyalty bonus discount based on the account's total spending
     * @param accountId Account to calculate the loyalty bonus for
     * @param amount Original purchase amount
     * @return discountedAmount The final amount after applying the loyalty bonus discount
     */
    function applyLoyaltyBonus(bytes32 accountId, uint256 amount) external view returns (uint256 discountedAmount) {
        require(accountId != bytes32(0), "Invalid account ID");
        require(amount > 0, "Amount must be greater than zero");

        uint256 totalSpending = getTotalSpending(accountId);
        uint256 bonusPercentage;

        if (totalSpending < 1000 ether) {
            bonusPercentage = 0; // No bonus for total spending under 1000 tokens
        } else if (totalSpending < 5000 ether) {
            bonusPercentage = 2; // 2% bonus for total spending between 1000 and 4999 tokens
        } else if (totalSpending < 10000 ether) {
            bonusPercentage = 5; // 5% bonus for total spending between 5000 and 9999 tokens
        } else {
            bonusPercentage = 10; // 10% bonus for total spending of 10000 tokens or more
        }

        uint256 bonusAmount = amount.mul(bonusPercentage).div(100);
        return amount.sub(bonusAmount);
    }

    /**
     * @dev Retrieves the total spending for a given account
     * @param accountId Account to check
     * @return totalSpent The total amount spent by the account
     */
    function getTotalSpending(bytes32 accountId) internal view returns (uint256 totalSpent) {
        // In a real implementation, this would query a storage mapping or external service
        // For this example, we'll return a mock value
        return 5000 ether;
    }

    /**
     * @dev Applies a time-limited flash sale discount
     * @param amount Original purchase amount
     * @param timestamp Current timestamp
     * @return discountedAmount The final amount after applying the flash sale discount
     */
    function applyFlashSaleDiscount(uint256 amount, uint256 timestamp) external pure returns (uint256 discountedAmount) {
        require(amount > 0, "Amount must be greater than zero");

        // Define the flash sale period (e.g., 1 hour)
        uint256 flashSaleStart = 1625097600; // Example: July 1, 2023, 00:00:00 UTC
        uint256 flashSaleEnd = flashSaleStart + 1 hours;

        if (timestamp >= flashSaleStart && timestamp < flashSaleEnd) {
            // Apply a 30% discount during the flash sale
            uint256 discountAmount = amount.mul(30).div(100);
            return amount.sub(discountAmount);
        } else {
            // No discount outside the flash sale period
            return amount;
        }
    }

    /**
     * @dev Applies a bulk purchase discount based on the quantity of items
     * @param unitPrice Price per item
     * @param quantity Number of items being purchased
     * @return totalDiscountedAmount The final total amount after applying the bulk discount
     */
    function applyBulkDiscount(uint256 unitPrice, uint256 quantity) external pure returns (uint256 totalDiscountedAmount) {
        require(unitPrice > 0, "Unit price must be greater than zero");
        require(quantity > 0, "Quantity must be greater than zero");

        uint256 discountPercentage;

        if (quantity < 10) {
            discountPercentage = 0; // No discount for less than 10 items
        } else if (quantity < 50) {
            discountPercentage = 5; // 5% discount for 10-49 items
        } else if (quantity < 100) {
            discountPercentage = 10; // 10% discount for 50-99 items
        } else {
            discountPercentage = 15; // 15% discount for 100 or more items
        }

        uint256 totalAmount = unitPrice.mul(quantity);
        uint256 discountAmount = totalAmount.mul(discountPercentage).div(100);
        return totalAmount.sub(discountAmount);
    }

    /**
     * @dev Applies a referral discount when a new customer is referred
     * @param amount Original purchase amount
     * @param referrerAccountId Account ID of the referrer
     * @return discountedAmount The final amount after applying the referral discount
     */
    function applyReferralDiscount(uint256 amount, bytes32 referrerAccountId) external view returns (uint256 discountedAmount) {
        require(amount > 0, "Amount must be greater than zero");
        require(referrerAccountId != bytes32(0), "Invalid referrer account ID");

        // Check if the referrer is valid and eligible to provide a discount
        if (isValidReferrer(referrerAccountId)) {
            // Apply a 10% discount for referred purchases
            uint256 discountAmount = amount.mul(10).div(100);
            return amount.sub(discountAmount);
        } else {
            // No discount if the referrer is not valid
            return amount;
        }
    }

    /**

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
        
        uint256 discountPercentage;
        
        if (purchasedCounts < 5) {
            discountPercentage = 5; // 5% discount for first 5 purchases
        } else if (purchasedCounts < 10) {
            discountPercentage = 10; // 10% discount for 6-10 purchases
        } else if (purchasedCounts < 20) {
            discountPercentage = 15; // 15% discount for 11-20 purchases
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
     * @param memo Human readable transfer description
     * @param traceId Unique identifier for tracking this transaction
     * @return bool indicating success of the operation
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
     * @param memo Human readable transfer description
     * @param traceId Unique identifier for tracking this transaction
     * @return bool indicating success of the operation
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
     * @dev Get the number of purchases for a given account
     * @param accountId The account to check
     * @return The number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) public view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Increment the purchase count for an account
     * @param accountId The account to increment the count for
     */
    function incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Reset the purchase count for an account
     * @param accountId The account to reset the count for
     * @notice Only callable by admin
     */
    function resetPurchaseCount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = 0;
    }

    /**
     * @dev Set a custom discount rate for a specific account
     * @param accountId The account to set the custom discount for
     * @param discountRate The custom discount rate (in percentage)
     * @notice Only callable by admin
     */
    function setCustomDiscount(bytes32 accountId, uint256 discountRate) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");
        customDiscounts[accountId] = discountRate;
        emit CustomDiscountSet(accountId, discountRate);
    }

    /**
     * @dev Remove a custom discount rate for a specific account
     * @param accountId The account to remove the custom discount from
     * @notice Only callable by admin
     */
    function removeCustomDiscount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        delete customDiscounts[accountId];
        emit CustomDiscountRemoved(accountId);
    }

    /**
     * @dev Get the custom discount rate for a specific account
     * @param accountId The account to check
     * @return The custom discount rate, or 0 if not set
     */
    function getCustomDiscount(bytes32 accountId) public view returns (uint256) {
        return customDiscounts[accountId];
    }

    /**
     * @dev Set a promotional discount for a specific item
     * @param item The item identifier
     * @param discountRate The promotional discount rate (in percentage)
     * @param expirationTime The timestamp when the promotion expires
     * @notice Only callable by admin
     */
    function setPromotionalDiscount(bytes32 item, uint256 discountRate, uint256 expirationTime) external onlyAdmin {
        require(item != bytes32(0), "Invalid item");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");
        require(expirationTime > block.timestamp, "Expiration time must be in the future");
        
        promotionalDiscounts[item] = PromotionalDiscount({
            rate: discountRate,
            expirationTime: expirationTime
        });
        
        emit PromotionalDiscountSet(item, discountRate, expirationTime);
    }

    /**
     * @dev Remove a promotional discount for a specific item
     * @param item The item identifier
     * @notice Only callable by admin
     */
    function removePromotionalDiscount(bytes32 item) external onlyAdmin {
        require(item != bytes32(0), "Invalid item");
        delete promotionalDiscounts[item];
        emit PromotionalDiscountRemoved(item);
    }

    /**
     * @dev Get the promotional discount rate for a specific item
     * @param item The item identifier
     * @return The promotional discount rate, or 0 if not set or expired
     */
    function getPromotionalDiscount(bytes32 item) public view returns (uint256) {
        PromotionalDiscount memory promo = promotionalDiscounts[item];
        if (promo.expirationTime > block.timestamp) {
            return promo.rate;
        }
        return 0;
    }

    /**
     * @dev Calculate the final discounted amount considering all discount types
     * @param accountId The account making the purchase
     * @param item The item being purchased
     * @param amount The original purchase amount
     * @param purchasedCounts The number of previous purchases by the account
     * @return The final discounted amount
     */
    function calculateFinalDiscount(bytes32 accountId, bytes32 item, uint256 amount, uint256 purchasedCounts) public view returns (uint256) {
        uint256 baseDiscount = discount(amount, purchasedCounts);
        uint256 customDiscountRate = getCustomDiscount(accountId);
        uint256 promoDiscountRate = getPromotionalDiscount(item);
        
        uint256 finalAmount = baseDiscount;
        
        if (customDiscountRate > 0) {
            finalAmount = finalAmount.sub(finalAmount.mul(customDiscountRate).div(100));
        }
        
        if (promoDiscountRate > 0) {
            finalAmount = finalAmount.sub(finalAmount.mul(promoDiscountRate).div(100));
        }
        
        return finalAmount;
    }

    /**
     * @dev Execute a purchase with all applicable discounts
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Human readable transfer description
     * @param traceId Unique identifier for tracking this transaction
     * @return bool indicating success of the operation
     */
    function executePurchaseWithAllDiscounts(
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
        uint256 finalAmount = calculateFinalDiscount(sendAccountId, item, amount, purchasedCounts);
        
        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            finalAmount,
            item,
            bytes32(purchasedCounts),
            memo,
            traceId
        );
        
        if (transferResult) {
            emit Discount(sendAccountId, item, amount, finalAmount);
            incrementPurchaseCount(sendAccountId);
        }
        
        return transferResult;
    }

    /**
     * @dev Get discount statistics for an account
     * @param accountId The account to get statistics for
     * @return totalPurchases The total number of purchases made
     * @return totalDiscountAmount The total amount saved through discounts
     * @return averageDiscountRate The average discount rate applied
     */
    function getAccountDiscountStatistics(bytes32 accountId) external view returns (uint256 totalPurchases, uint256 totalDiscountAmount, uint256 averageDiscountRate) {
        require(accountId != bytes32(0), "Invalid accountId");
        
        totalPurchases = getPurchaseCount(accountId);
        totalDiscountAmount = accountDiscountStats[accountId].totalDiscountAmount;
        
        if (totalPurchases > 0) {
            averageDiscountRate = totalDiscountAmount.mul(100).div(accountDiscountStats[accountId].totalOriginalAmount);
        }
    }

    /**
     * @dev Update discount statistics for an account after a purchase
     * @param accountId The account to update statistics for
     * @param originalAmount The original amount before discount
     * @param discountedAmount The final amount after discount
     */
    function _updateAccountDiscountStatistics(bytes32 accountId, uint256 originalAmount, uint256 discountedAmount) internal {
        uint256 discountAmount = originalAmount.sub(discountedAmount);
        accountDiscountStats[accountId].totalDiscountAmount = accountDiscountStats[accountId].totalDiscountAmount.add(discountAmount);
        accountDiscountStats[accountId].totalOriginalAmount = accountDiscountStats[accountId].totalOriginalAmount.add(originalAmount);
    }

    /**
     * @dev Get global discount statistics
     * @return totalDiscountsApplied The total number of discounts applied
     * @return totalDiscountAmount The total amount saved through discounts across all accounts
     * @return averageDiscountRate The global average discount rate
     */
    function getGlobalDiscountStatistics() external view returns (uint256 totalDiscountsApplied, uint256 totalDiscountAmount, uint256 averageDiscountRate) {
        totalDiscountsApplied = globalDiscountStats.totalDiscountsApplied;
        totalDiscountAmount = globalDiscountStats.totalDiscountAmount;
        
        if (globalDiscountStats.totalOriginalAmount > 0) {
            averageDiscountRate = totalDiscountAmount.mul(100).div(globalDiscountStats.totalOriginalAmount);
        }
    }

    /**
     * @dev Update global discount statistics after a purchase
     * @param originalAmount The original amount before discount
     * @param discountedAmount The final amount after discount
     */
    function _updateGlobalDiscountStatistics(uint256 originalAmount, uint256 discountedAmount) internal {
        uint256 discountAmount = originalAmount.sub(discountedAmount);
        globalDiscountStats.totalDiscountsApplied = globalDiscountStats.totalDiscountsApplied.add(1);
        globalDiscountStats.totalDiscountAmount = globalDiscountStats.totalDiscountAmount.add(discountAmount);
        globalDiscountStats.totalOriginalAmount = globalDiscountStats.totalOriginalAmount.add(originalAmount);
    }

    /**
     * @dev Set a bulk discount tier
     * @param minAmount The minimum purchase amount for this tier
     * @param discountRate The discount rate for this tier (in percentage)
     * @notice Only callable by admin
     */
    function setBulkDiscountTier(uint256 minAmount, uint256 discountRate) external onlyAdmin {
        require(minAmount > 0, "Minimum amount must be greater than zero");
        require(discountRate <= 100, "Discount rate cannot exceed 100%");
        
        bulkDiscountTiers.push(BulkDiscountTier({
            minAmount: minAmount,
            discountRate: discountRate
        }));
        
        // Sort tiers by minAmount in descending order
        for (uint i = bulkDiscountTiers.length - 1; i > 0; i--) {
            if (bulkDiscountTiers[i].minAmount > bulkDiscountTiers[i-1].minAmount) {
                BulkDiscountTier memory temp = bulkDiscountTiers[i-1];
                bulkDiscountTiers[i-1] = bulkDiscountTiers[i];
                bulkDiscountTiers[i] = temp;
            } else {
                break;
            }
        }
        
        emit BulkDiscountTierSet(minAmount, discountRate);
    }

    /**
     * @dev Remove a bulk discount tier
     * @param index The index of the tier to remove
     * @notice Only callable by admin
     */
    function removeBulkDiscountTier(uint256 index) external onlyAdmin {
        require(index < bulkDiscountTiers.length, "Invalid tier index");
        
        uint256 minAmount = bulkDiscountTiers[index