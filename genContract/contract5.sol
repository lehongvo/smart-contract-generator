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
    
    // Mapping to store account balances
    mapping(bytes32 => uint256) private accountBalances;
    
    // Mapping to store account purchase counts
    mapping(bytes32 => uint256) private accountPurchaseCounts;
    
    // Mapping to store active accounts
    mapping(bytes32 => bool) private activeAccounts;

    // Events
    event OracleUpdated(uint256 indexed oldOracleId, uint256 indexed newOracleId);
    event AccountCreated(bytes32 indexed accountId);
    event AccountDeactivated(bytes32 indexed accountId);
    event BalanceUpdated(bytes32 indexed accountId, uint256 oldBalance, uint256 newBalance);

    // Modifiers
    modifier onlyActiveAccount(bytes32 accountId) {
        require(activeAccounts[accountId], "Account is not active");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    modifier validAccountId(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    // Constructor
    constructor() {
        _pause(); // Initially paused until initialization
    }

    /**
     * @dev Initializes discount contract with dependencies
     * @param _oracle Oracle contract for price/discount data
     * @param _token Token contract for payment handling
     * @notice Can only be called once during deployment
     * @notice Validates oracle and token addresses
     */
    function initialize(IOracle _oracle, ITransferable _token) external override initializer {
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");
        
        oracle = _oracle;
        token = _token;
        oracleId = 1; // Default oracle ID
        
        _unpause();
        _transferOwnership(msg.sender);
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
     * @notice Only admin can update
     * @notice Validates oracle exists and is active
     */
    function setOracleId(uint256 _oracleId) external override onlyOwner {
        require(_oracleId > 0, "Invalid oracle ID");
        
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        require(value == bytes32(uint256(1)), "Oracle is not active");
        
        uint256 oldOracleId = oracleId;
        oracleId = _oracleId;
        
        emit OracleUpdated(oldOracleId, _oracleId);
    }

    /**
     * @dev Gets current oracle ID
     * @return Currently active oracle identifier
     */
    function getOracleId() external view override returns (uint256) {
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
    function discount(uint256 amount, uint256 purchasedCounts) external pure override validAmount(amount) returns (uint256) {
        uint256 discountPercentage;
        
        if (purchasedCounts >= 100) {
            discountPercentage = 20;
        } else if (purchasedCounts >= 50) {
            discountPercentage = 15;
        } else if (purchasedCounts >= 25) {
            discountPercentage = 10;
        } else if (purchasedCounts >= 10) {
            discountPercentage = 5;
        } else {
            discountPercentage = 0;
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
    ) external override nonReentrant whenNotPaused returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        require(activeAccounts[sendAccountId], "Send account is not active");
        require(activeAccounts[fromAccountId], "From account is not active");
        require(activeAccounts[toAccountId], "To account is not active");

        require(accountBalances[fromAccountId] >= amount, "Insufficient balance in source account");

        // Update balances
        accountBalances[fromAccountId] = accountBalances[fromAccountId].sub(amount);
        accountBalances[toAccountId] = accountBalances[toAccountId].add(amount);

        // Update purchase count for the sender
        accountPurchaseCounts[sendAccountId] = accountPurchaseCounts[sendAccountId].add(1);

        // Emit transfer event
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);

        // Emit balance update events
        emit BalanceUpdated(fromAccountId, accountBalances[fromAccountId].add(amount), accountBalances[fromAccountId]);
        emit BalanceUpdated(toAccountId, accountBalances[toAccountId].sub(amount), accountBalances[toAccountId]);

        return true;
    }

    /**
     * @dev Creates a new account in the system
     * @param accountId Unique identifier for the new account
     * @notice Only callable by system admin
     * @notice Account must not already exist
     */
    function createAccount(bytes32 accountId) external onlyOwner validAccountId(accountId) {
        require(!activeAccounts[accountId], "Account already exists");
        
        activeAccounts[accountId] = true;
        accountBalances[accountId] = 0;
        accountPurchaseCounts[accountId] = 0;
        
        emit AccountCreated(accountId);
    }

    /**
     * @dev Deactivates an existing account
     * @param accountId Identifier of the account to deactivate
     * @notice Only callable by system admin
     * @notice Account must exist and be active
     */
    function deactivateAccount(bytes32 accountId) external onlyOwner validAccountId(accountId) onlyActiveAccount(accountId) {
        activeAccounts[accountId] = false;
        
        emit AccountDeactivated(accountId);
    }

    /**
     * @dev Retrieves the balance of a specific account
     * @param accountId Identifier of the account to query
     * @return Balance of the specified account
     * @notice Account must exist and be active
     */
    function getAccountBalance(bytes32 accountId) external view validAccountId(accountId) onlyActiveAccount(accountId) returns (uint256) {
        return accountBalances[accountId];
    }

    /**
     * @dev Retrieves the purchase count of a specific account
     * @param accountId Identifier of the account to query
     * @return Purchase count of the specified account
     * @notice Account must exist and be active
     */
    function getAccountPurchaseCount(bytes32 accountId) external view validAccountId(accountId) onlyActiveAccount(accountId) returns (uint256) {
        return accountPurchaseCounts[accountId];
    }

    /**
     * @dev Applies a discount to a purchase and updates balances
     * @param accountId Account making the purchase
     * @param item Identifier of the item being purchased
     * @param amount Original price of the item
     * @notice Account must exist and be active
     * @notice Amount must be greater than zero
     */
    function applyDiscount(bytes32 accountId, bytes32 item, uint256 amount) external nonReentrant whenNotPaused validAccountId(accountId) onlyActiveAccount(accountId) validAmount(amount) {
        uint256 purchaseCount = accountPurchaseCounts[accountId];
        uint256 discountedAmount = this.discount(amount, purchaseCount);
        
        require(accountBalances[accountId] >= discountedAmount, "Insufficient balance for purchase");
        
        accountBalances[accountId] = accountBalances[accountId].sub(discountedAmount);
        accountPurchaseCounts[accountId] = purchaseCount.add(1);
        
        emit Discount(accountId, item, amount, discountedAmount);
        emit BalanceUpdated(accountId, accountBalances[accountId].add(discountedAmount), accountBalances[accountId]);
    }

    /**
     * @dev Adds balance to an account
     * @param accountId Account to add balance to
     * @param amount Amount to add to the balance
     * @notice Only callable by system admin
     * @notice Account must exist and be active
     * @notice Amount must be greater than zero
     */
    function addBalance(bytes32 accountId, uint256 amount) external onlyOwner validAccountId(accountId) onlyActiveAccount(accountId) validAmount(amount) {
        uint256 oldBalance = accountBalances[accountId];
        accountBalances[accountId] = oldBalance.add(amount);
        
        emit BalanceUpdated(accountId, oldBalance, accountBalances[accountId]);
    }

    /**
     * @dev Removes balance from an account
     * @param accountId Account to remove balance from
     * @param amount Amount to remove from the balance
     * @notice Only callable by system admin
     * @notice Account must exist and be active
     * @notice Amount must be greater than zero and not exceed current balance
     */
    function removeBalance(bytes32 accountId, uint256 amount) external onlyOwner validAccountId(accountId) onlyActiveAccount(accountId) validAmount(amount) {
        require(accountBalances[accountId] >= amount, "Insufficient balance");
        
        uint256 oldBalance = accountBalances[accountId];
        accountBalances[accountId] = oldBalance.sub(amount);
        
        emit BalanceUpdated(accountId, oldBalance, accountBalances[accountId]);
    }

    /**
     * @dev Pauses all contract functions
     * @notice Only callable by contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all contract functions
     * @notice Only callable by contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // Internal helper functions

    /**
     * @dev Internal function to validate and apply a discount
     * @param amount Original amount
     * @param discountPercentage Percentage of discount to apply
     * @return Discounted amount
     */
    function _applyDiscountPercentage(uint256 amount, uint256 discountPercentage) internal pure returns (uint256) {
        require(discountPercentage <= 100, "Invalid discount percentage");
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if an account is eligible for a special discount
     * @param accountId Account to check
     * @return True if eligible, false otherwise
     */
    function _isEligibleForSpecialDiscount(bytes32 accountId) internal view returns (bool) {
        return accountPurchaseCounts[accountId] > 100 && accountBalances[accountId] > 10000;
    }

    // Additional helper functions...

    // ... (continued in next parts)

}

    /**
     * @dev Initializes discount contract with dependencies
     * @param oracle Oracle contract for price/discount data
     * @param token Token contract for payment handling
     * @notice Can only be called once during deployment
     * @notice Validates oracle and token addresses
     */
    function initialize(IOracle oracle, ITransferable token) external override {
        require(!initialized, "Contract already initialized");
        require(address(oracle) != address(0), "Invalid oracle address");
        require(address(token) != address(0), "Invalid token address");

        oracleContract = oracle;
        tokenContract = token;
        initialized = true;

        emit ContractInitialized(address(oracle), address(token));
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
     * @param oracleId New oracle ID to use
     * @notice Only admin can update
     * @notice Validates oracle exists and is active
     */
    function setOracleId(uint256 oracleId) external override onlyAdmin {
        require(oracleId > 0, "Invalid oracle ID");
        
        (bytes32 value, string memory err) = oracleContract.get(oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        require(value == bytes32(uint256(1)), "Oracle is not active");

        currentOracleId = oracleId;
        emit OracleIdUpdated(oracleId);
    }

    /**
     * @dev Gets current oracle ID
     * @return Currently active oracle identifier
     */
    function getOracleId() external view override returns (uint256) {
        return currentOracleId;
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

        uint256 discountRate;
        if (purchasedCounts == 0) {
            discountRate = 0; // No discount for first purchase
        } else if (purchasedCounts < 5) {
            discountRate = 5; // 5% discount for 1-4 purchases
        } else if (purchasedCounts < 10) {
            discountRate = 10; // 10% discount for 5-9 purchases
        } else {
            discountRate = 15; // 15% discount for 10+ purchases
        }

        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
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
     * @notice Validates all accounts exist and are active
     * @notice Checks sufficient balance in source account
     * @notice Applies discount based on purchase history
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
    ) external override returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Get purchase history
        uint256 purchasedCounts = getPurchaseHistory(sendAccountId);

        // Calculate discounted amount
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Execute transfer
        bool transferResult = tokenContract.customTransfer(
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

        // Update purchase history
        updatePurchaseHistory(sendAccountId);

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
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, accountId);
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Account lookup failed");
        return value == bytes32(uint256(1));
    }

    /**
     * @dev Gets account balance
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("BALANCE_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Balance lookup failed");
        return uint256(value);
    }

    /**
     * @dev Gets purchase history count for an account
     * @param accountId Account to check
     * @return uint256 Number of purchases
     */
    function getPurchaseHistory(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("PURCHASES_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Purchase history lookup failed");
        return uint256(value);
    }

    /**
     * @dev Updates purchase history for an account
     * @param accountId Account to update
     */
    function updatePurchaseHistory(bytes32 accountId) internal {
        uint256 currentPurchases = getPurchaseHistory(accountId);
        uint256 newPurchases = currentPurchases.add(1);
        oracleContract.set(currentOracleId, keccak256(abi.encodePacked("PURCHASES_", accountId)), bytes32(newPurchases));
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return uint256 Discount rate percentage
     */
    function getDiscountRate(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount == 0) {
            return 0;
        } else if (purchaseCount < 5) {
            return 5;
        } else if (purchaseCount < 10) {
            return 10;
        } else {
            return 15;
        }
    }

    /**
     * @dev Calculates the discounted price for a given amount and purchase count
     * @param amount Original price
     * @param purchaseCount Number of previous purchases
     * @return uint256 Discounted price
     */
    function calculateDiscountedPrice(uint256 amount, uint256 purchaseCount) public pure returns (uint256) {
        uint256 discountRate = getDiscountRate(purchaseCount);
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Retrieves the discount amount for a given price and purchase count
     * @param amount Original price
     * @param purchaseCount Number of previous purchases
     * @return uint256 Discount amount
     */
    function getDiscountAmount(uint256 amount, uint256 purchaseCount) public pure returns (uint256) {
        uint256 discountedPrice = calculateDiscountedPrice(amount, purchaseCount);
        return amount.sub(discountedPrice);
    }

    /**
     * @dev Checks if a discount is applicable for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return bool True if discount is applicable
     */
    function isDiscountApplicable(uint256 purchaseCount) public pure returns (bool) {
        return getDiscountRate(purchaseCount) > 0;
    }

    /**
     * @dev Retrieves the next discount milestone for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return uint256 Number of purchases needed for next discount tier
     */
    function getNextDiscountMilestone(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount < 5) {
            return 5 - purchaseCount;
        } else if (purchaseCount < 10) {
            return 10 - purchaseCount;
        } else {
            return 0; // Already at maximum discount
        }
    }

    /**
     * @dev Calculates the savings amount for a given price and purchase count
     * @param amount Original price
     * @param purchaseCount Number of previous purchases
     * @return uint256 Amount saved due to discount
     */
    function calculateSavings(uint256 amount, uint256 purchaseCount) public pure returns (uint256) {
        uint256 discountedPrice = calculateDiscountedPrice(amount, purchaseCount);
        return amount.sub(discountedPrice);
    }

    /**
     * @dev Retrieves the discount tier for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return uint256 Discount tier (0-3)
     */
    function getDiscountTier(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount == 0) {
            return 0;
        } else if (purchaseCount < 5) {
            return 1;
        } else if (purchaseCount < 10) {
            return 2;
        } else {
            return 3;
        }
    }

    /**
     * @dev Calculates the effective discount rate for a given amount and purchase count
     * @param amount Original price
     * @param purchaseCount Number of previous purchases
     * @return uint256 Effective discount rate as a percentage
     */
    function calculateEffectiveDiscountRate(uint256 amount, uint256 purchaseCount) public pure returns (uint256) {
        uint256 discountAmount = getDiscountAmount(amount, purchaseCount);
        return discountAmount.mul(100).div(amount);
    }

    /**
     * @dev Estimates the number of purchases needed to reach a specific discount rate
     * @param targetDiscountRate Desired discount rate percentage
     * @return uint256 Estimated number of purchases needed
     */
    function estimatePurchasesForDiscountRate(uint256 targetDiscountRate) public pure returns (uint256) {
        require(targetDiscountRate <= 15, "Target discount rate too high");
        
        if (targetDiscountRate == 0) {
            return 0;
        } else if (targetDiscountRate <= 5) {
            return 1;
        } else if (targetDiscountRate <= 10) {
            return 5;
        } else {
            return 10;
        }
    }

    /**
     * @dev Calculates the total savings over a series of purchases
     * @param amounts Array of purchase amounts
     * @return uint256 Total amount saved
     */
    function calculateTotalSavings(uint256[] memory amounts) public pure returns (uint256) {
        uint256 totalSavings = 0;
        uint256 purchaseCount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 discountedPrice = calculateDiscountedPrice(amounts[i], purchaseCount);
            totalSavings = totalSavings.add(amounts[i].sub(discountedPrice));
            purchaseCount = purchaseCount.add(1);
        }

        return totalSavings;
    }

    /**
     * @dev Simulates the discount progression for a series of purchases
     * @param amounts Array of purchase amounts
     * @return uint256[] Array of discounted prices
     */
    function simulateDiscountProgression(uint256[] memory amounts) public pure returns (uint256[] memory) {
        uint256[] memory discountedPrices = new uint256[](amounts.length);
        uint256 purchaseCount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            discountedPrices[i] = calculateDiscountedPrice(amounts[i], purchaseCount);
            purchaseCount = purchaseCount.add(1);
        }

        return discountedPrices;
    }

    /**
     * @dev Calculates the average discount rate over a series of purchases
     * @param amounts Array of purchase amounts
     * @return uint256 Average discount rate as a percentage
     */
    function calculateAverageDiscountRate(uint256[] memory amounts) public pure returns (uint256) {
        require(amounts.length > 0, "Empty amounts array");

        uint256 totalDiscountRate = 0;
        uint256 purchaseCount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            totalDiscountRate = totalDiscountRate.add(calculateEffectiveDiscountRate(amounts[i], purchaseCount));
            purchaseCount = purchaseCount.add(1);
        }

        return totalDiscountRate.div(amounts.length);
    }

    /**
     * @dev Estimates the time to reach maximum discount based on average purchase frequency
     * @param averagePurchaseFrequency Average number of days between purchases
     * @return uint256 Estimated number of days to reach maximum discount
     */
    function estimateTimeToMaxDiscount(uint256 averagePurchaseFrequency) public pure returns (uint256) {
        require(averagePurchaseFrequency > 0, "Invalid average purchase frequency");

        uint256 purchasesNeeded = 10; // Purchases needed for max discount
        return purchasesNeeded.mul(averagePurchaseFrequency);
    }

    /**
     * @dev Calculates the break-even point for a subscription model vs. pay-per-use with discounts
     * @param subscriptionPrice Monthly subscription price
     * @param payPerUsePrice Price per use without discount
     * @return uint256

Here is PART 3 of the smart contract implementation:

// BEGIN PART 3

    /**
     * @dev Calculates the discount percentage based on purchase history
     * @param purchasedCounts Number of previous purchases
     * @return Discount percentage (0-100)
     */
    function calculateDiscountPercentage(uint256 purchasedCounts) internal pure returns (uint256) {
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

    /**
     * @dev Applies the discount to the original amount
     * @param amount Original purchase amount
     * @param discountPercentage Discount percentage to apply
     * @return Discounted amount
     */
    function applyDiscount(uint256 amount, uint256 discountPercentage) internal pure returns (uint256) {
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Validates the purchase amount
     * @param amount Amount to validate
     */
    function validateAmount(uint256 amount) internal pure {
        require(amount > 0, "Purchase amount must be greater than zero");
    }

    /**
     * @dev Validates the account ID
     * @param accountId Account ID to validate
     */
    function validateAccountId(bytes32 accountId) internal pure {
        require(accountId != bytes32(0), "Account ID cannot be empty");
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account ID to check
     * @return True if the account is active, false otherwise
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        // Implementation depends on how account status is stored
        // This is a placeholder implementation
        return true;
    }

    /**
     * @dev Checks if an account has sufficient balance
     * @param accountId Account ID to check
     * @param amount Amount to check against
     * @return True if the account has sufficient balance, false otherwise
     */
    function hasSufficientBalance(bytes32 accountId, uint256 amount) internal view returns (bool) {
        // Implementation depends on how balances are stored
        // This is a placeholder implementation
        return true;
    }

    /**
     * @dev Generates a unique trace ID for a transaction
     * @return Unique trace ID
     */
    function generateTraceId() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender));
    }

    /**
     * @dev Logs a discount event
     * @param sendAccountId Account receiving the discount
     * @param item Identifier of purchased item
     * @param originalAmount Original price before discount
     * @param discountedAmount Final price after discount applied
     */
    function logDiscountEvent(bytes32 sendAccountId, bytes32 item, uint256 originalAmount, uint256 discountedAmount) internal {
        emit Discount(sendAccountId, item, originalAmount, discountedAmount);
    }

    /**
     * @dev Fetches the current discount rate from the oracle
     * @return Current discount rate
     */
    function fetchDiscountRate() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to fetch discount rate from oracle");
        return uint256(value);
    }

    /**
     * @dev Applies any additional business logic for discounts
     * @param sendAccountId Account receiving the discount
     * @param amount Original purchase amount
     * @param discountedAmount Calculated discounted amount
     * @return Final discounted amount after applying additional logic
     */
    function applyAdditionalDiscountLogic(bytes32 sendAccountId, uint256 amount, uint256 discountedAmount) internal view returns (uint256) {
        // This is a placeholder for any additional business logic
        // For example, we could apply a minimum discount amount:
        uint256 minDiscountAmount = 100; // Minimum discount of 100 tokens
        uint256 actualDiscount = amount.sub(discountedAmount);
        if (actualDiscount < minDiscountAmount) {
            return amount.sub(minDiscountAmount);
        }
        return discountedAmount;
    }

    /**
     * @dev Validates the oracle ID
     * @param _oracleId Oracle ID to validate
     */
    function validateOracleId(uint256 _oracleId) internal view {
        require(_oracleId > 0, "Oracle ID must be greater than zero");
        // Additional checks could be added here, e.g., checking if the oracle exists in the Oracle contract
    }

    /**
     * @dev Updates the purchase history for an account
     * @param accountId Account ID to update
     */
    function updatePurchaseHistory(bytes32 accountId) internal {
        // Implementation depends on how purchase history is stored
        // This is a placeholder implementation
        purchaseHistory[accountId] = purchaseHistory[accountId].add(1);
    }

    /**
     * @dev Calculates the final price after applying all discounts and promotions
     * @param originalAmount Original purchase amount
     * @param discountedAmount Amount after applying standard discount
     * @param sendAccountId Account making the purchase
     * @return Final price after all discounts and promotions
     */
    function calculateFinalPrice(uint256 originalAmount, uint256 discountedAmount, bytes32 sendAccountId) internal view returns (uint256) {
        uint256 finalPrice = discountedAmount;

        // Apply any seasonal promotions
        if (isSeasonalPromotionActive()) {
            uint256 seasonalDiscount = calculateSeasonalDiscount(originalAmount);
            finalPrice = finalPrice.sub(seasonalDiscount);
        }

        // Apply any loyalty bonuses
        uint256 loyaltyBonus = calculateLoyaltyBonus(sendAccountId, originalAmount);
        finalPrice = finalPrice.sub(loyaltyBonus);

        // Ensure the final price doesn't go below a minimum threshold
        uint256 minPrice = originalAmount.mul(MIN_PRICE_PERCENTAGE).div(100);
        return finalPrice > minPrice ? finalPrice : minPrice;
    }

    /**
     * @dev Checks if a seasonal promotion is currently active
     * @return True if a seasonal promotion is active, false otherwise
     */
    function isSeasonalPromotionActive() internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "SEASONAL_PROMOTION_ACTIVE");
        require(bytes(err).length == 0, "Failed to fetch seasonal promotion status from oracle");
        return value != bytes32(0);
    }

    /**
     * @dev Calculates the seasonal discount amount
     * @param amount Original purchase amount
     * @return Seasonal discount amount
     */
    function calculateSeasonalDiscount(uint256 amount) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "SEASONAL_DISCOUNT_PERCENTAGE");
        require(bytes(err).length == 0, "Failed to fetch seasonal discount percentage from oracle");
        uint256 seasonalDiscountPercentage = uint256(value);
        return amount.mul(seasonalDiscountPercentage).div(100);
    }

    /**
     * @dev Calculates the loyalty bonus for an account
     * @param accountId Account ID to calculate bonus for
     * @param amount Original purchase amount
     * @return Loyalty bonus amount
     */
    function calculateLoyaltyBonus(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        uint256 loyaltyScore = getLoyaltyScore(accountId);
        uint256 bonusPercentage = loyaltyScore.div(100); // 1% bonus for every 100 loyalty points
        return amount.mul(bonusPercentage).div(100);
    }

    /**
     * @dev Gets the loyalty score for an account
     * @param accountId Account ID to get score for
     * @return Loyalty score
     */
    function getLoyaltyScore(bytes32 accountId) internal view returns (uint256) {
        // Implementation depends on how loyalty scores are stored
        // This is a placeholder implementation
        return purchaseHistory[accountId].mul(10); // 10 points per purchase
    }

    /**
     * @dev Applies any referral bonuses to the purchase
     * @param sendAccountId Account making the purchase
     * @param amount Purchase amount
     * @return Updated purchase amount after applying referral bonus
     */
    function applyReferralBonus(bytes32 sendAccountId, uint256 amount) internal returns (uint256) {
        bytes32 referrer = getReferrer(sendAccountId);
        if (referrer != bytes32(0)) {
            uint256 bonusAmount = amount.mul(REFERRAL_BONUS_PERCENTAGE).div(100);
            // Credit bonus to referrer
            token.customTransfer(bytes32(0), bytes32(0), referrer, bonusAmount, bytes32(0), bytes32(0), "Referral bonus", generateTraceId());
            // Deduct bonus from purchase amount
            return amount.sub(bonusAmount);
        }
        return amount;
    }

    /**
     * @dev Gets the referrer for an account
     * @param accountId Account ID to get referrer for
     * @return Referrer account ID
     */
    function getReferrer(bytes32 accountId) internal view returns (bytes32) {
        // Implementation depends on how referrals are stored
        // This is a placeholder implementation
        return bytes32(0);
    }

    /**
     * @dev Validates and processes a bulk discount purchase
     * @param sendAccountId Account initiating the purchase
     * @param items Array of item identifiers
     * @param amounts Array of purchase amounts for each item
     * @return totalDiscountedAmount Total discounted amount for all items
     */
    function processBulkDiscount(bytes32 sendAccountId, bytes32[] memory items, uint256[] memory amounts) internal returns (uint256) {
        require(items.length == amounts.length, "Items and amounts arrays must have the same length");
        require(items.length > 0, "Must purchase at least one item");

        uint256 totalOriginalAmount = 0;
        uint256 totalDiscountedAmount = 0;

        for (uint256 i = 0; i < items.length; i++) {
            validateAmount(amounts[i]);
            totalOriginalAmount = totalOriginalAmount.add(amounts[i]);

            uint256 discountedAmount = discount(amounts[i], purchaseHistory[sendAccountId]);
            totalDiscountedAmount = totalDiscountedAmount.add(discountedAmount);

            logDiscountEvent(sendAccountId, items[i], amounts[i], discountedAmount);
        }

        // Apply bulk purchase discount
        uint256 bulkDiscountPercentage = calculateBulkDiscountPercentage(items.length);
        totalDiscountedAmount = applyDiscount(totalDiscountedAmount, bulkDiscountPercentage);

        // Apply any additional discounts or promotions
        totalDiscountedAmount = applyAdditionalDiscountLogic(sendAccountId, totalOriginalAmount, totalDiscountedAmount);

        // Update purchase history
        updatePurchaseHistory(sendAccountId);

        return totalDiscountedAmount;
    }

    /**
     * @dev Calculates the bulk discount percentage based on the number of items
     * @param itemCount Number of items in the bulk purchase
     * @return Bulk discount percentage
     */
    function calculateBulkDiscountPercentage(uint256 itemCount) internal pure returns (uint256) {
        if (itemCount >= 10) {
            return 15; // 15% discount for 10+ items
        } else if (itemCount >= 5) {
            return 10; // 10% discount for 5-9 items
        } else if (itemCount >= 3) {
            return 5; // 5% discount for 3-4 items
        } else {
            return 0; // No bulk discount for less than 3 items
        }
    }

    /**
     * @dev Processes a flash sale discount if active
     * @param amount Original purchase amount
     * @return Discounted amount after applying flash sale discount
     */
    function processFlashSaleDiscount(uint256 amount) internal view returns (uint256) {
        if (isFlashSaleActive()) {
            uint256 flashSaleDiscountPercentage = getFlashSaleDiscountPercentage();
            return applyDiscount(amount, flashSaleDiscountPercentage);
        }
        return amount;
    }

    /**
     * @dev Checks if a flash sale is currently active
     * @return True if a flash sale is active, false otherwise
     */
    function isFlashSaleActive() internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "FLASH_SALE_ACTIVE");
        require(bytes(err).length == 0, "Failed to fetch flash sale status from oracle");
        return value != bytes32(0);
    }

    /**
     * @dev Gets the current flash sale discount percentage
     * @return Flash sale discount percentage
     */
    function getFlashSaleDiscountPercentage() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "FLASH_SALE_DISCOUNT_PERCENTAGE");
        require(bytes(err).length == 0, "Failed to fetch flash sale discount percentage from oracle");
        return uint256(value);
    }

    /**
     * @dev Applies a tiered pricing model based on purchase amount
     * @param amount Original purchase amount
     * @return Discounted amount after applying tiered pricing
     */
    function applyTieredPricing(uint256 amount) internal pure returns (uint256) {
        if (amount >= 10000) {
            return applyDiscount(amount, 25); // 25% discount for purchases of 10000 or more
        } else if (amount >= 5000) {
            return applyDiscount(amount, 20); // 20% discount for purchases between 5000 and 9999
        } else if (amount >= 1000) {
            return applyDiscount(amount, 15); // 15% discount for purchases between 1000 and 4999
        } else {
            return amount; // No additional discount for purchases under 1000
        }
    }

    /**
     * @dev Calculates and applies a dynamic discount based on current market conditions
     * @param amount Original purchase amount
     * @return Discounted amount after applying dynamic discount
     */
    function applyDynamicDiscount(uint256 amount) internal view returns (uint256) {
        uint256 marketVolatility = getMarketVolatility();
        uint256 dynamicDiscountPercentage = calculateDynamicDiscountPercentage(marketVolatility);
        return applyDiscount(amount, dynamicDiscountPercentage);
    }

    /**
     * @dev Gets the current market volatility from the oracle
     * @return Market volatility value
     */
    function getMarketVolatility() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "MARKET_VOLATILITY");
        require(bytes(err).length == 0, "Failed to fetch market volatility from oracle");
        return uint256(value);
    }

    /**
     * @dev Calculates the dynamic discount percentage based on market volatility
     * @param marketVolatility Current market volatility
     * @return Dynamic discount percentage
     */
    function calculateDynamicDiscountPercentage(uint256 marketVolatility) internal pure returns (uint256) {
        // Example: Higher volatility leads to higher
        // discounts, capped at 50% for extreme volatility
        return marketVolatility > 50 ? 50 : marketVolatility;
    }
}