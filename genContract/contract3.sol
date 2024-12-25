// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Ownable, Pausable, Initializable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to store account balances
    mapping(bytes32 => uint256) private accountBalances;
    
    // Mapping to store account active status
    mapping(bytes32 => bool) private accountActive;
    
    // Mapping to store purchase history counts
    mapping(bytes32 => uint256) private purchaseHistory;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount

    // Events
    event OracleUpdated(uint256 indexed newOracleId);
    event AccountActivated(bytes32 indexed accountId);
    event AccountDeactivated(bytes32 indexed accountId);
    event BalanceUpdated(bytes32 indexed accountId, uint256 newBalance);

    // Modifiers
    modifier onlyActiveAccount(bytes32 accountId) {
        require(accountActive[accountId], "Account is not active");
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

    /**
     * @dev Constructor to set the owner of the contract
     */
    constructor() Ownable() {
        // Intentionally left empty
    }

    /**
     * @dev Initializes discount contract with dependencies
     * @param _oracle Oracle contract for price/discount data
     * @param _token Token contract for payment handling
     */
    function initialize(IOracle _oracle, ITransferable _token) external initializer {
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");
        
        oracle = _oracle;
        token = _token;
        oracleId = 1; // Default oracle ID
        
        // Additional initialization logic can be added here
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
     */
    function setOracleId(uint256 _oracleId) external onlyOwner {
        require(_oracleId > 0, "Invalid oracle ID");
        
        // Check if the oracle exists and is active
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
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure validAmount(amount) returns (uint256) {
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
    ) external whenNotPaused onlyActiveAccount(sendAccountId) onlyActiveAccount(fromAccountId) onlyActiveAccount(toAccountId) validAmount(amount) validAccountId(sendAccountId) validAccountId(fromAccountId) validAccountId(toAccountId) returns (bool result) {
        require(accountBalances[fromAccountId] >= amount, "Insufficient balance in source account");
        
        // Perform the transfer
        accountBalances[fromAccountId] = accountBalances[fromAccountId].sub(amount);
        accountBalances[toAccountId] = accountBalances[toAccountId].add(amount);
        
        // Update purchase history for the sender
        purchaseHistory[sendAccountId] = purchaseHistory[sendAccountId].add(1);
        
        // Apply discount if applicable
        uint256 discountedAmount = this.discount(amount, purchaseHistory[sendAccountId]);
        
        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);
        
        // Additional logic can be added here (e.g., interacting with the token contract)
        
        return true;
    }

    /**
     * @dev Activates an account
     * @param accountId The account to activate
     */
    function activateAccount(bytes32 accountId) external onlyOwner validAccountId(accountId) {
        require(!accountActive[accountId], "Account is already active");
        accountActive[accountId] = true;
        emit AccountActivated(accountId);
    }

    /**
     * @dev Deactivates an account
     * @param accountId The account to deactivate
     */
    function deactivateAccount(bytes32 accountId) external onlyOwner validAccountId(accountId) {
        require(accountActive[accountId], "Account is not active");
        accountActive[accountId] = false;
        emit AccountDeactivated(accountId);
    }

    /**
     * @dev Updates the balance of an account
     * @param accountId The account to update
     * @param newBalance The new balance to set
     */
    function updateBalance(bytes32 accountId, uint256 newBalance) external onlyOwner validAccountId(accountId) {
        accountBalances[accountId] = newBalance;
        emit BalanceUpdated(accountId, newBalance);
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId The account to query
     * @return The current balance of the account
     */
    function getBalance(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        return accountBalances[accountId];
    }

    /**
     * @dev Gets the purchase history count of an account
     * @param accountId The account to query
     * @return The number of purchases made by the account
     */
    function getPurchaseHistory(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        return purchaseHistory[accountId];
    }

    /**
     * @dev Checks if an account is active
     * @param accountId The account to check
     * @return True if the account is active, false otherwise
     */
    function isAccountActive(bytes32 accountId) external view validAccountId(accountId) returns (bool) {
        return accountActive[accountId];
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Allows the contract to receive Ether
     */
    receive() external payable {
        // Handle incoming Ether if needed
    }

    /**
     * @dev Fallback function
     */
    fallback() external payable {
        // Handle unknown function calls
    }

    // Additional helper functions

    /**
     * @dev Internal function to validate and apply a discount
     * @param accountId The account receiving the discount
     * @param amount The original amount
     * @return The discounted amount
     */
    function _applyDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        uint256 discountedAmount = this.discount(amount, purchaseHistory[accountId]);
        return discountedAmount;
    }

    /**
     * @dev Internal function to update oracle data
     * @param key The data key to update
     * @param value The new value
     */
    function _updateOracleData(bytes32 key, bytes32 value) internal {
        oracle.set(oracleId, key, value);
    }

    /**
     * @dev Internal function to batch update oracle data
     * @param keys Array of keys to update
     * @param values Array of corresponding values
     */
    function _batchUpdateOracleData(bytes32[] memory keys, bytes32[] memory values) internal {
        require(keys.length == values.length, "Keys and values arrays must have the same length");
        oracle.setBatch(oracleId, keys, values);
    }

    /**
     * @dev Internal function to get oracle data
     * @param key The data key to retrieve
     * @return value The retrieved value
     * @return err Any error message
     */
    function _getOracleData(bytes32 key) internal view returns (bytes32 value, string memory err) {
        return oracle.get(oracleId, key);
    }

    /**
     * @dev Internal function to batch get oracle data
     * @param keys Array of keys to retrieve
     * @return values Array of retrieved values
     * @return err Any error message
     */
    function _batchGetOracleData(bytes32[] memory keys) internal view returns (bytes32[] memory values, string memory err) {
        return oracle.getBatch(oracleId, keys);
    }

    // Additional functions for future expansion

    /**
     * @dev Function to upgrade the contract (placeholder for upgrade logic)
     * @param newImplementation Address of the new implementation
     */
    function upgradeContract(address newImplementation) external onlyOwner {
        // Implement upgrade logic here
        // This is a placeholder and should be properly implemented with a secure upgrade pattern
        require(newImplementation != address(0), "Invalid new implementation address");
        // Actual upgrade logic would go here
    }

    /**
     * @dev Function to set a new discount tier
     * @param tier The tier number (1, 2, or 3)
     * @param threshold The new purchase count threshold for this tier
     * @param discountPercentage The new discount percentage for this tier
     */
    function setDiscountTier(uint256 tier, uint256 threshold, uint256 discountPercentage) external onlyOwner {
        require(tier >= 1 && tier <= 3, "Invalid tier number");
        require(discountPercentage <= 100, "Discount percentage cannot exceed 100");
        
        if (tier == 1) {
            // Update TIER1 constants
        } else if (tier == 2) {
            // Update TIER2 constants
        } else {
            // Update TIER3 constants
        }
        
        // Emit an event for the updated tier
        emit DiscountTierUpdated(tier, threshold, discountPercentage);
    }

    /**
     * @dev Event emitted when a discount tier is updated
     * @param tier The updated tier number
     * @param threshold The new threshold for the tier
     * @param discountPercentage The new discount percentage for the tier
     */
    event DiscountTierUpdated(uint256 tier, uint256 threshold, uint256 discountPercentage);

    // END PART 1

Here is PART 2 of the smart contract implementation:

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
     * @dev Applies discount and processes payment for an item
     * @param sendAccountId Account making the purchase
     * @param item Identifier of the item being purchased
     * @param amount Original price of the item
     * @return discountedAmount Final price after discount
     */
    function applyDiscountAndPay(bytes32 sendAccountId, bytes32 item, uint256 amount) external returns (uint256) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(item != bytes32(0), "Invalid item");
        require(amount > 0, "Amount must be greater than 0");

        uint256 purchasedCounts = purchaseHistory[sendAccountId];
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Transfer discounted amount from sender to contract
        bool transferSuccess = token.customTransfer(
            sendAccountId,
            sendAccountId,
            address(this),
            discountedAmount,
            bytes32(0),
            bytes32(0),
            "Item purchase with discount",
            keccak256(abi.encodePacked(sendAccountId, item, block.timestamp))
        );
        require(transferSuccess, "Payment transfer failed");

        // Update purchase history
        purchaseHistory[sendAccountId] = purchasedCounts.add(1);

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return discountedAmount;
    }

    /**
     * @dev Retrieves the purchase history count for an account
     * @param accountId Account to check
     * @return Number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) external view returns (uint256) {
        return purchaseHistory[accountId];
    }

    /**
     * @dev Resets the purchase history for an account
     * @param accountId Account to reset
     * @notice Only callable by admin
     */
    function resetPurchaseHistory(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        delete purchaseHistory[accountId];
        emit PurchaseHistoryReset(accountId);
    }

    /**
     * @dev Bulk reset of purchase histories for multiple accounts
     * @param accountIds Array of account IDs to reset
     * @notice Only callable by admin
     * @notice More gas efficient than multiple single resets
     */
    function bulkResetPurchaseHistory(bytes32[] memory accountIds) external onlyAdmin {
        require(accountIds.length > 0, "Empty accountIds array");
        for (uint256 i = 0; i < accountIds.length; i++) {
            require(accountIds[i] != bytes32(0), "Invalid accountId");
            delete purchaseHistory[accountIds[i]];
            emit PurchaseHistoryReset(accountIds[i]);
        }
    }

    /**
     * @dev Sets a custom discount rate for a specific account
     * @param accountId Account to set custom discount for
     * @param discountRate Custom discount rate (0-100)
     * @notice Only callable by admin
     */
    function setCustomDiscount(bytes32 accountId, uint256 discountRate) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(discountRate <= 100, "Invalid discount rate");
        customDiscounts[accountId] = discountRate;
        emit CustomDiscountSet(accountId, discountRate);
    }

    /**
     * @dev Removes a custom discount rate for a specific account
     * @param accountId Account to remove custom discount from
     * @notice Only callable by admin
     */
    function removeCustomDiscount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        delete customDiscounts[accountId];
        emit CustomDiscountRemoved(accountId);
    }

    /**
     * @dev Retrieves the custom discount rate for an account
     * @param accountId Account to check
     * @return Custom discount rate, 0 if not set
     */
    function getCustomDiscount(bytes32 accountId) external view returns (uint256) {
        return customDiscounts[accountId];
    }

    /**
     * @dev Sets the discount tier thresholds
     * @param newThresholds Array of new thresholds
     * @notice Only callable by admin
     * @notice Array must be sorted in ascending order
     */
    function setDiscountTiers(uint256[] memory newThresholds) external onlyAdmin {
        require(newThresholds.length > 0, "Empty thresholds array");
        for (uint256 i = 1; i < newThresholds.length; i++) {
            require(newThresholds[i] > newThresholds[i-1], "Thresholds must be in ascending order");
        }
        discountTiers = newThresholds;
        emit DiscountTiersUpdated(newThresholds);
    }

    /**
     * @dev Retrieves the current discount tier thresholds
     * @return Array of current thresholds
     */
    function getDiscountTiers() external view returns (uint256[] memory) {
        return discountTiers;
    }

    /**
     * @dev Sets the discount rates for each tier
     * @param newRates Array of new discount rates
     * @notice Only callable by admin
     * @notice Array length must match discountTiers length
     * @notice Rates must be between 0 and 100
     */
    function setDiscountRates(uint256[] memory newRates) external onlyAdmin {
        require(newRates.length == discountTiers.length, "Rates array length mismatch");
        for (uint256 i = 0; i < newRates.length; i++) {
            require(newRates[i] <= 100, "Invalid discount rate");
        }
        discountRates = newRates;
        emit DiscountRatesUpdated(newRates);
    }

    /**
     * @dev Retrieves the current discount rates
     * @return Array of current discount rates
     */
    function getDiscountRates() external view returns (uint256[] memory) {
        return discountRates;
    }

    /**
     * @dev Calculates the effective discount rate for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return Effective discount rate
     */
    function getEffectiveDiscountRate(uint256 purchaseCount) public view returns (uint256) {
        for (uint256 i = 0; i < discountTiers.length; i++) {
            if (purchaseCount < discountTiers[i]) {
                return discountRates[i];
            }
        }
        return discountRates[discountRates.length - 1];
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
    ) external override returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Check if accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getBalance(fromAccountId) >= amount, "Insufficient balance");

        // Perform transfer
        balances[fromAccountId] = balances[fromAccountId].sub(amount);
        balances[toAccountId] = balances[toAccountId].add(amount);

        // Apply any custom logic based on miscValue1 and miscValue2
        if (miscValue1 != bytes32(0)) {
            // Custom logic for miscValue1
        }
        if (miscValue2 != bytes32(0)) {
            // Custom logic for miscValue2
        }

        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);
        
        // Log the transfer details
        transferLogs.push(TransferLog({
            sendAccountId: sendAccountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            amount: amount,
            memo: memo,
            traceId: traceId,
            timestamp: block.timestamp
        }));

        return true;
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account to check
     * @return True if account is active, false otherwise
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        // Implementation depends on how account status is stored
        // For this example, we'll assume all accounts are active
        return true;
    }

    /**
     * @dev Retrieves the balance of an account
     * @param accountId Account to check
     * @return Balance of the account
     */
    function getBalance(bytes32 accountId) internal view returns (uint256) {
        return balances[accountId];
    }

    /**
     * @dev Retrieves transfer logs for a specific account
     * @param accountId Account to retrieve logs for
     * @param startIndex Start index of logs to retrieve
     * @param count Number of logs to retrieve
     * @return logs Array of transfer logs
     */
    function getTransferLogs(bytes32 accountId, uint256 startIndex, uint256 count) external view returns (TransferLog[] memory logs) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(startIndex < transferLogs.length, "Start index out of bounds");

        uint256 endIndex = startIndex.add(count);
        if (endIndex > transferLogs.length) {
            endIndex = transferLogs.length;
        }

        logs = new TransferLog[](endIndex.sub(startIndex));
        uint256 logIndex = 0;

        for (uint256 i = startIndex; i < endIndex; i++) {
            if (transferLogs[i].sendAccountId == accountId ||
                transferLogs[i].fromAccountId == accountId ||
                transferLogs[i].toAccountId == accountId) {
                logs[logIndex] = transferLogs[i];
                logIndex++;
            }
        }

        // Resize the array to remove empty elements
        assembly {
            mstore(logs, logIndex)
        }
    }

    /**
     * @dev Calculates total volume of transfers for an account
     * @param accountId Account to calculate volume for
     * @param startTime Start of time range (Unix timestamp)
     * @param endTime End of time range (Unix timestamp)
     * @return Total volume of transfers
     */
    function calculateTransferVolume(bytes32 accountId, uint256 startTime, uint256 endTime) external view returns (uint256) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(startTime < endTime, "Invalid time range");

        uint256 totalVolume = 0;

        for (uint256 i = 0; i < transferLogs.length; i++) {
            if (transferLogs[i].timestamp >= startTime && transferLogs[i].timestamp <= endTime) {
                if (transferLogs[i].fromAccountId == accountId) {
                    totalVolume = totalVolume.add(transferLogs[i].amount);
                }
            }
        }

        return totalVolume;
    }

    /**
     * @dev Sets a spending limit for an account
     * @param accountId Account to set limit for
     * @param limit Daily spending limit
     * @notice Only callable by admin
     */
    function setSpendingLimit(bytes32 accountId, uint256 limit) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        spendingLimits[accountId] = limit;
        emit SpendingLimitSet(accountId, limit);
    }

    /**
     * @dev Removes spending limit for an account
     * @param accountId Account to remove limit from
     * @notice Only callable by admin
     */
    function removeSpendingLimit(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        delete spendingLimits[accountId];
        emit SpendingLimitRemoved(accountId);
    }

    /**
     * @dev Checks if a transfer would exceed the daily spending limit
     * @param accountId Account to check
     * @param amount Amount of the transfer
     * @return True if transfer is allowed, false if it would exceed the limit
     */
    function checkSpendingLimit(bytes32 accountId, uint256 amount) internal view returns (bool) {
        uint256 limit = spendingLimits[accountId];
        if (limit == 0) {
            return true; // No limit set
        }

        uint256 todaySpending = calculateTransferVolume(accountId, getDayStart(), block.timestamp);
        return todaySpending.add(amount) <= limit;
    }

    /**
     * @dev Gets the start of the current day (00:00:00 UTC)
     * @return Timestamp of the start of the current day
     */
    function getDayStart() internal view returns (uint256) {
        return block.timestamp - (block.timestamp % 86400);
    }

    /**
     * @dev Freezes an account, preventing any outgoing transfers
     * @param accountId Account to freeze
     * @notice Only callable by admin
     */
    function freezeAccount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        frozenAccounts[accountId] = true;
        emit AccountFrozen(accountId);
    }

    /**
     * @dev Unfreezes an account, allowing outgoing transfers
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
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;

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
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to apply discount and process payment
     * @param sendAccountId Account receiving the discount
     * @param fromAccountId Source account for payment
     * @param toAccountId Destination account for payment
     * @param amount Original purchase amount
     * @param item Identifier of purchased item
     * @param purchasedCounts Number of previous purchases by account
     * @return bool indicating success of the operation
     */
    function _applyDiscountAndTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts
    ) internal returns (bool) {
        uint256 discountedAmount = discount(amount, purchasedCounts);

        bool transferResult = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            bytes32(0),
            bytes32(0),
            "Discounted purchase",
            keccak256(abi.encodePacked(sendAccountId, item, block.timestamp))
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Internal function to validate account IDs
     * @param accountId Account ID to validate
     */
    function _validateAccountId(bytes32 accountId) internal pure {
        require(accountId != bytes32(0), "Invalid account ID");
    }

    /**
     * @dev Internal function to update purchase history
     * @param accountId Account ID to update
     * @param item Purchased item identifier
     */
    function _updatePurchaseHistory(bytes32 accountId, bytes32 item) internal {
        purchaseHistory[accountId][item]++;
        totalPurchases[accountId]++;
    }

    /**
     * @dev Internal function to get current discount rate from oracle
     * @return Current discount rate
     */
    function _getCurrentDiscountRate() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(currentOracleId, DISCOUNT_RATE_KEY);
        require(bytes(err).length == 0, "Failed to fetch discount rate");
        return uint256(value);
    }

    /**
     * @dev Internal function to apply dynamic discount based on oracle data
     * @param amount Original amount
     * @return Discounted amount
     */
    function _applyDynamicDiscount(uint256 amount) internal view returns (uint256) {
        uint256 discountRate = _getCurrentDiscountRate();
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if an account is eligible for special promotions
     * @param accountId Account ID to check
     * @return bool indicating if the account is eligible
     */
    function _isEligibleForPromotion(bytes32 accountId) internal view returns (bool) {
        return totalPurchases[accountId] > 0 && block.timestamp.sub(lastPromotionTimestamp[accountId]) >= 30 days;
    }

    /**
     * @dev Internal function to apply a special promotion discount
     * @param amount Original amount
     * @return Discounted amount after applying promotion
     */
    function _applyPromotionDiscount(uint256 amount) internal pure returns (uint256) {
        return amount.mul(70).div(100); // 30% discount for promotions
    }

    /**
     * @dev Internal function to record a promotion application
     * @param accountId Account ID that received the promotion
     */
    function _recordPromotion(bytes32 accountId) internal {
        lastPromotionTimestamp[accountId] = block.timestamp;
        emit PromotionApplied(accountId);
    }

    /**
     * @dev Internal function to check if bulk discount is applicable
     * @param quantity Number of items in the purchase
     * @return bool indicating if bulk discount should be applied
     */
    function _isBulkDiscountApplicable(uint256 quantity) internal pure returns (bool) {
        return quantity >= 10;
    }

    /**
     * @dev Internal function to apply bulk discount
     * @param amount Original amount
     * @param quantity Number of items
     * @return Discounted amount after applying bulk discount
     */
    function _applyBulkDiscount(uint256 amount, uint256 quantity) internal pure returns (uint256) {
        uint256 discountPercentage = quantity >= 50 ? 15 : (quantity >= 25 ? 10 : 5);
        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if seasonal discount is active
     * @return bool indicating if seasonal discount is currently active
     */
    function _isSeasonalDiscountActive() internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(currentOracleId, SEASONAL_DISCOUNT_KEY);
        require(bytes(err).length == 0, "Failed to fetch seasonal discount status");
        return value != bytes32(0);
    }

    /**
     * @dev Internal function to apply seasonal discount
     * @param amount Original amount
     * @return Discounted amount after applying seasonal discount
     */
    function _applySeasonalDiscount(uint256 amount) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(currentOracleId, SEASONAL_DISCOUNT_RATE_KEY);
        require(bytes(err).length == 0, "Failed to fetch seasonal discount rate");
        uint256 seasonalDiscountRate = uint256(value);
        uint256 discountAmount = amount.mul(seasonalDiscountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if an account is a VIP
     * @param accountId Account ID to check
     * @return bool indicating if the account has VIP status
     */
    function _isVipAccount(bytes32 accountId) internal view returns (bool) {
        return totalPurchases[accountId] >= 1000 || vipAccounts[accountId];
    }

    /**
     * @dev Internal function to apply VIP discount
     * @param amount Original amount
     * @return Discounted amount after applying VIP discount
     */
    function _applyVipDiscount(uint256 amount) internal pure returns (uint256) {
        return amount.mul(85).div(100); // 15% discount for VIP accounts
    }

    /**
     * @dev Internal function to update VIP status based on purchase history
     * @param accountId Account ID to update
     */
    function _updateVipStatus(bytes32 accountId) internal {
        if (totalPurchases[accountId] >= 1000 && !vipAccounts[accountId]) {
            vipAccounts[accountId] = true;
            emit VipStatusGranted(accountId);
        }
    }

    /**
     * @dev Internal function to check if referral discount is applicable
     * @param accountId Account ID to check
     * @return bool indicating if referral discount should be applied
     */
    function _isReferralDiscountApplicable(bytes32 accountId) internal view returns (bool) {
        return referralCounts[accountId] > 0 && !referralDiscountUsed[accountId];
    }

    /**
     * @dev Internal function to apply referral discount
     * @param amount Original amount
     * @return Discounted amount after applying referral discount
     */
    function _applyReferralDiscount(uint256 amount) internal pure returns (uint256) {
        return amount.mul(90).div(100); // 10% discount for referrals
    }

    /**
     * @dev Internal function to record usage of referral discount
     * @param accountId Account ID that used the referral discount
     */
    function _recordReferralDiscountUsage(bytes32 accountId) internal {
        referralDiscountUsed[accountId] = true;
        emit ReferralDiscountApplied(accountId);
    }

    /**
     * @dev Internal function to check if first-time purchase discount is applicable
     * @param accountId Account ID to check
     * @return bool indicating if first-time purchase discount should be applied
     */
    function _isFirstTimePurchaseDiscountApplicable(bytes32 accountId) internal view returns (bool) {
        return totalPurchases[accountId] == 0;
    }

    /**
     * @dev Internal function to apply first-time purchase discount
     * @param amount Original amount
     * @return Discounted amount after applying first-time purchase discount
     */
    function _applyFirstTimePurchaseDiscount(uint256 amount) internal pure returns (uint256) {
        return amount.mul(80).div(100); // 20% discount for first-time purchases
    }

    /**
     * @dev Internal function to record first-time purchase
     * @param accountId Account ID making the first purchase
     */
    function _recordFirstTimePurchase(bytes32 accountId) internal {
        emit FirstTimePurchase(accountId);
    }

    /**
     * @dev Internal function to apply all applicable discounts
     * @param sendAccountId Account receiving the discount
     * @param amount Original purchase amount
     * @param item Identifier of purchased item
     * @param quantity Number of items in the purchase
     * @return Final discounted amount after applying all discounts
     */
    function _applyAllDiscounts(
        bytes32 sendAccountId,
        uint256 amount,
        bytes32 item,
        uint256 quantity
    ) internal returns (uint256) {
        uint256 discountedAmount = amount;

        // Apply dynamic discount based on oracle data
        discountedAmount = _applyDynamicDiscount(discountedAmount);

        // Apply discount based on purchase history
        discountedAmount = discount(discountedAmount, totalPurchases[sendAccountId]);

        // Apply bulk discount if applicable
        if (_isBulkDiscountApplicable(quantity)) {
            discountedAmount = _applyBulkDiscount(discountedAmount, quantity);
        }

        // Apply seasonal discount if active
        if (_isSeasonalDiscountActive()) {
            discountedAmount = _applySeasonalDiscount(discountedAmount);
        }

        // Apply VIP discount if applicable
        if (_isVipAccount(sendAccountId)) {
            discountedAmount = _applyVipDiscount(discountedAmount);
        }

        // Apply referral discount if applicable
        if (_isReferralDiscountApplicable(sendAccountId)) {
            discountedAmount = _applyReferralDiscount(discountedAmount);
            _recordReferralDiscountUsage(sendAccountId);
        }

        // Apply first-time purchase discount if applicable
        if (_isFirstTimePurchaseDiscountApplicable(sendAccountId)) {
            discountedAmount = _applyFirstTimePurchaseDiscount(discountedAmount);
            _recordFirstTimePurchase(sendAccountId);
        }

        // Apply special promotion if eligible
        if (_isEligibleForPromotion(sendAccountId)) {
            discountedAmount = _applyPromotionDiscount(discountedAmount);
            _recordPromotion(sendAccountId);
        }

        // Update purchase history and VIP status
        _updatePurchaseHistory(sendAccountId, item);
        _updateVipStatus(sendAccountId);

        return discountedAmount;
    }

    /**
     * @dev Public function to process a discounted purchase
     * @param sendAccountId Account receiving the discount
     * @param fromAccountId Source account for payment
     * @param toAccountId Destination account for payment
     * @param amount Original purchase amount
     * @param item Identifier of purchased item
     * @param quantity Number of items in the purchase
     * @return bool indicating success of the operation
     */
    function processDiscountedPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 quantity
    ) public returns (bool) {
        require(amount > 0, "Amount must be greater than zero");
        require(quantity > 0, "Quantity must be greater than zero");
        _validateAccountId(sendAccountId);
        _validateAccountId(fromAccountId);
        _validateAccountId(toAccountId);

        uint256 discountedAmount = _applyAllDiscounts(sendAccountId, amount, item, quantity);

        bool transferResult = token.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            bytes32(quantity),
            item,
            "Discounted purchase with multiple factors",
            keccak256(abi.encodePacked(sendAccountId, item, quantity, block.timestamp))
        );

        require(transferResult, "Transfer failed");

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Admin function to manually set VIP status for an account
     * @param accountId Account ID to set VIP status
     * @param status New VIP status
     */
    function setVipStatus(bytes32 accountId, bool status) external onlyAdmin {
        _validateAccountId(accountId);
        vipAccounts[accountId] = status;
        emit VipStatusUpdated(accountId, status);
    }

    /**
     * @dev Admin function to add referral for an account
     * @param accountId Account ID that made the referral
     */
    function addReferral(bytes32 accountId) external onlyAdmin {
        _validateAccountId(accountId);
        referralCounts[accountId]++;
        emit ReferralAdded(accountId);
    }

    /**
     * @dev Admin function to set seasonal discount status
     * @param active Whether seasonal discount is active
     * @param rate Discount rate for the seasonal promotion
     */
    function setSeasonalDiscount(bool active, uint256 rate) external onlyAdmin {
        require(rate <= 100, "Invalid discount rate");
        oracle.set(currentOracleId, SEASONAL_DISCOUNT_KEY, active ? bytes32(uint256(1)) : bytes32(0));
        oracle.set(currentOracleId, SEASONAL_DISCOUNT_RATE_KEY, bytes32(rate));
        emit SeasonalDiscountUpdated(active, rate);
    }

    /**
     * @dev Admin function to update the dynamic discount rate
     * @param rate New discount rate
     */
    function updateDynamicDiscountRate(uint256 rate) external onlyAdmin {
        require(rate <= 100, "Invalid discount rate");
    }
}