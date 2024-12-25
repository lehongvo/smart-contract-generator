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
    
    // Mapping to track purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;
    
    // Discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    // Discount rates (in basis points, e.g. 500 = 5%)
    uint256 private constant TIER1_DISCOUNT = 500;
    uint256 private constant TIER2_DISCOUNT = 1000;
    uint256 private constant TIER3_DISCOUNT = 1500;
    
    // Events
    event OracleUpdated(uint256 oldOracleId, uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyActiveOracle(uint256 _oracleId) {
        require(_oracleId > 0, "Invalid oracle ID");
        (bytes32 isActive, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(isActive == bytes32(uint256(1)), string(abi.encodePacked("Oracle not active: ", err)));
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    // Constructor
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
        oracleId = 1; // Default to first oracle
        
        // Additional initialization logic can be added here
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

        // Tiered discount rates based on purchase history
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
     * @param toAccountId Destination account (usually the merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by the account
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
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

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
     * @dev Retrieves the current discount rate from the oracle
     * @return discountRate The current discount rate as a percentage
     */
    function getCurrentDiscountRate() public view returns (uint256 discountRate) {
        (bytes32 rateValue, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Error fetching discount rate");
        return uint256(rateValue);
    }

    /**
     * @dev Updates the discount rate in the oracle
     * @param newRate New discount rate to set (as a percentage)
     * @notice Only callable by the contract owner
     */
    function updateDiscountRate(uint256 newRate) external onlyOwner {
        require(newRate <= 100, "Discount rate cannot exceed 100%");
        oracle.set(oracleId, "DISCOUNT_RATE", bytes32(newRate));
        emit DiscountRateUpdated(newRate);
    }

    /**
     * @dev Applies a special promotional discount to a purchase
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually the merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param promoCode Promotional code for additional discount
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the promotional purchase was successful
     */
    function promotionalPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        bytes32 promoCode,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(promoCode != bytes32(0), "Invalid promo code");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 promoDiscount = getPromoDiscount(promoCode);
        uint256 discountedAmount = amount.sub(promoDiscount);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            promoCode,
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);
        emit PromotionalDiscount(sendAccountId, item, promoCode, promoDiscount);

        return true;
    }

    /**
     * @dev Retrieves the discount amount for a given promotional code
     * @param promoCode Promotional code to check
     * @return discount The discount amount for the given promo code
     */
    function getPromoDiscount(bytes32 promoCode) public view returns (uint256 discount) {
        (bytes32 discountValue, string memory err) = oracle.get(oracleId, promoCode);
        require(bytes(err).length == 0, "Error fetching promo discount");
        return uint256(discountValue);
    }

    /**
     * @dev Sets a new promotional discount
     * @param promoCode Promotional code to set
     * @param discountAmount Discount amount for the promo code
     * @notice Only callable by the contract owner
     */
    function setPromoDiscount(bytes32 promoCode, uint256 discountAmount) external onlyOwner {
        require(promoCode != bytes32(0), "Invalid promo code");
        require(discountAmount > 0, "Discount amount must be greater than zero");
        oracle.set(oracleId, promoCode, bytes32(discountAmount));
        emit PromoDiscountSet(promoCode, discountAmount);
    }

    /**
     * @dev Removes a promotional discount
     * @param promoCode Promotional code to remove
     * @notice Only callable by the contract owner
     */
    function removePromoDiscount(bytes32 promoCode) external onlyOwner {
        require(promoCode != bytes32(0), "Invalid promo code");
        oracle.set(oracleId, promoCode, bytes32(0));
        emit PromoDiscountRemoved(promoCode);
    }

    /**
     * @dev Applies a bulk discount to multiple items in a single transaction
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually the merchant)
     * @param amounts Array of original purchase amounts for each item
     * @param items Array of identifiers for the items being purchased
     * @param purchasedCounts Array of previous purchase counts for each item
     * @param memo Description of the bulk purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the bulk discounted purchase was successful
     */
    function bulkDiscountedPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256[] memory amounts,
        bytes32[] memory items,
        uint256[] memory purchasedCounts,
        string memory memo,
        bytes32 traceId
    ) external returns (bool success) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amounts.length > 0, "No items to purchase");
        require(amounts.length == items.length && amounts.length == purchasedCounts.length, "Array lengths mismatch");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 totalDiscountedAmount = 0;
        uint256 totalOriginalAmount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than zero");
            uint256 discountedAmount = discount(amounts[i], purchasedCounts[i]);
            totalDiscountedAmount = totalDiscountedAmount.add(discountedAmount);
            totalOriginalAmount = totalOriginalAmount.add(amounts[i]);

            emit Discount(sendAccountId, items[i], amounts[i], discountedAmount);
        }

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            totalDiscountedAmount,
            bytes32("BULK_PURCHASE"),
            bytes32(amounts.length),
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit BulkDiscount(sendAccountId, totalOriginalAmount, totalDiscountedAmount, amounts.length);

        return true;
    }

    /**
     * @dev Applies a tiered discount based on the total purchase amount
     * @param amount Total purchase amount
     * @return discountedAmount The amount after applying the tiered discount
     */
    function tieredDiscount(uint256 amount) public view returns (uint256 discountedAmount) {
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;

        if (amount >= 10000 ether) {
            discountPercentage = 15; // 15% discount for purchases of 10,000 ETH or more
        } else if (amount >= 5000 ether) {
            discountPercentage = 10; // 10% discount for purchases between 5,000 and 9,999.99 ETH
        } else if (amount >= 1000 ether) {
            discountPercentage = 5; // 5% discount for purchases between 1,000 and 4,999.99 ETH
        } else {
            discountPercentage = 0; // No discount for purchases under 1,000 ETH
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Applies a time-based discount (e.g., happy hour discount)
     * @param amount Original purchase amount
     * @return discountedAmount The amount after applying the time-based discount
     */
    function timeBasedDiscount(uint256 amount) public view returns (uint256 discountedAmount) {
        require(amount > 0, "Amount must be greater than zero");

        uint256 currentHour = (block.timestamp / 3600) % 24;
        uint256 discountPercentage;

        if (currentHour >= 14 && currentHour < 18) {
            discountPercentage = 10; // 10% discount during happy hours (2 PM to 6 PM)
        } else {
            discountPercentage = 0; // No discount outside happy hours
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Applies a combination of discounts (loyalty, tiered, and time-based)
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually the merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param purchasedCounts Number of previous purchases by the account
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return success True if the combined discounted purchase was successful
     */
    function combinedDiscountPurchase(
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
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        uint256 loyaltyDiscountedAmount = discount(amount, purchasedCounts);
        uint256 tieredDiscountedAmount = tieredDiscount(loyaltyDiscountedAmount);
        uint256 finalDiscountedAmount = timeBasedDiscount(tieredDiscountedAmount);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            finalDiscountedAmount,
            item,
            bytes32(purchasedCounts),
            memo,
            traceId
        );

        require(transferResult, "Transfer failed");

        emit CombinedDiscount(sendAccountId, item, amount, finalDiscountedAmount);

        return true;
    }

    /**
     * @dev Calculates the potential savings for a given purchase amount
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by the account
     * @return loyaltySavings Savings from loyalty discount
     * @return tieredSavings Savings from tiered discount
     * @return timeBasedSavings Savings from time-based discount
     * @return totalSavings Total combined savings
     */
    function calculatePotentialSavings(uint256 amount, uint256 purchasedCounts) 
        external 
        view 
        returns (
            uint256 loyaltySavings, 
            uint256 tieredSavings, 
            uint256 timeBasedSavings, 
            uint256 totalSavings
        ) 
    {
        require(amount > 0, "Amount must be greater than zero");

        uint256 loyaltyDiscountedAmount = discount(amount, purchasedCounts);
        loyaltySavings = amount.sub(loyaltyDiscountedAmount);

        uint256 tieredDiscountedAmount = tieredDiscount(loyaltyDiscountedAmount);
        tieredSavings = loyaltyDiscountedAmount.sub(tieredDiscountedAmount);

        uint256

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
        require(amount > 0, "Amount must be greater than 0");
        
        uint256 discountPercentage;
        
        if (purchasedCounts == 0) {
            discountPercentage = 5; // 5% discount for first purchase
        } else if (purchasedCounts < 5) {
            discountPercentage = 10; // 10% discount for 2-4 purchases
        } else if (purchasedCounts < 10) {
            discountPercentage = 15; // 15% discount for 5-9 purchases
        } else {
            discountPercentage = 20; // 20% discount for 10+ purchases
        }
        
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        uint256 discountedAmount = amount.sub(discountAmount);
        
        return discountedAmount;
    }

    /**
     * @dev Internal function to validate account existence and activity
     * @param accountId Account to validate
     */
    function _validateAccount(bytes32 accountId) internal view {
        require(accountId != bytes32(0), "Invalid account ID");
        require(_accounts[accountId].isActive, "Account is not active");
    }

    /**
     * @dev Internal function to check if an address has admin privileges
     * @param addr Address to check
     * @return bool True if address has admin role
     */
    function _isAdmin(address addr) internal view returns (bool) {
        return _admins[addr];
    }

    /**
     * @dev Internal function to update account balance
     * @param accountId Account to update
     * @param amount Amount to add (or subtract if negative)
     */
    function _updateBalance(bytes32 accountId, int256 amount) internal {
        if (amount > 0) {
            _accounts[accountId].balance = _accounts[accountId].balance.add(uint256(amount));
        } else {
            _accounts[accountId].balance = _accounts[accountId].balance.sub(uint256(-amount));
        }
    }

    /**
     * @dev Internal function to get current discount rate from oracle
     * @return Discount rate as a percentage (e.g., 10 for 10%)
     */
    function _getDiscountRate() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(_oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to fetch discount rate");
        return uint256(value);
    }

    /**
     * @dev Internal function to apply discount to an amount
     * @param amount Original amount
     * @param discountRate Discount rate as a percentage
     * @return Discounted amount
     */
    function _applyDiscount(uint256 amount, uint256 discountRate) internal pure returns (uint256) {
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to log discount application
     * @param sendAccountId Account receiving the discount
     * @param item Identifier of purchased item
     * @param originalAmount Original price before discount
     * @param discountedAmount Final price after discount applied
     */
    function _logDiscount(bytes32 sendAccountId, bytes32 item, uint256 originalAmount, uint256 discountedAmount) internal {
        emit Discount(sendAccountId, item, originalAmount, discountedAmount);
    }

    /**
     * @dev Internal function to validate oracle
     * @param oracleId Oracle ID to validate
     */
    function _validateOracle(uint256 oracleId) internal view {
        require(oracleId > 0, "Invalid oracle ID");
        // Additional oracle validation logic here
    }

    /**
     * @dev Internal function to execute a transfer between accounts
     * @param fromAccountId Source account
     * @param toAccountId Destination account
     * @param amount Amount to transfer
     */
    function _executeTransfer(bytes32 fromAccountId, bytes32 toAccountId, uint256 amount) internal {
        _validateAccount(fromAccountId);
        _validateAccount(toAccountId);
        require(_accounts[fromAccountId].balance >= amount, "Insufficient balance");
        
        _updateBalance(fromAccountId, -int256(amount));
        _updateBalance(toAccountId, int256(amount));
    }

    /**
     * @dev Internal function to generate a unique trace ID
     * @return bytes32 Unique trace ID
     */
    function _generateTraceId() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender));
    }

    /**
     * @dev Internal function to validate transfer parameters
     * @param sendAccountId Account initiating the transfer
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account
     * @param amount Number of tokens to transfer
     */
    function _validateTransferParams(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount
    ) internal view {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than 0");
        _validateAccount(sendAccountId);
        _validateAccount(fromAccountId);
        _validateAccount(toAccountId);
    }

    /**
     * @dev Internal function to handle custom transfer logic
     * @param sendAccountId Account initiating the transfer
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account
     * @param amount Number of tokens to transfer
     * @param miscValue1 First auxiliary parameter for transfer logic
     * @param miscValue2 Second auxiliary parameter for transfer logic
     * @return bool True if transfer completed successfully
     */
    function _handleCustomTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2
    ) internal returns (bool) {
        // Custom transfer logic implementation
        // This is a placeholder and should be replaced with actual business logic
        
        // Example: Apply a discount based on miscValue1
        uint256 discountRate = uint256(miscValue1);
        uint256 discountedAmount = _applyDiscount(amount, discountRate);
        
        // Execute the transfer with the discounted amount
        _executeTransfer(fromAccountId, toAccountId, discountedAmount);
        
        // Log the discount application
        _logDiscount(sendAccountId, miscValue2, amount, discountedAmount);
        
        return true;
    }

    /**
     * @dev Internal function to validate and process a batch of key-value pairs
     * @param keys Array of data identifiers to update
     * @param values Array of corresponding values to store
     */
    function _processBatch(bytes32[] memory keys, bytes32[] memory values) internal pure {
        require(keys.length == values.length, "Keys and values arrays must have equal length");
        for (uint256 i = 0; i < keys.length; i++) {
            require(keys[i] != bytes32(0), "Invalid key at index");
            // Additional validation for values can be added here if needed
        }
    }

    /**
     * @dev Internal function to upgrade the contract
     * @param newImplementation Address of the new implementation contract
     */
    function _upgrade(address newImplementation) internal {
        require(newImplementation != address(0), "Invalid implementation address");
        require(newImplementation != address(this), "Cannot upgrade to same implementation");
        
        // Perform upgrade logic here
        // This is a placeholder and should be replaced with actual upgrade mechanism
        
        emit ContractUpgraded(address(this), newImplementation);
    }

    /**
     * @dev Emitted when the contract is upgraded
     * @param oldImplementation Address of the old implementation contract
     * @param newImplementation Address of the new implementation contract
     */
    event ContractUpgraded(address indexed oldImplementation, address indexed newImplementation);

    // Additional helper functions and implementation details can be added here as needed

}