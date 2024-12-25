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
    
    // Mapping to track purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;
    
    // Discount tiers
    uint256 constant TIER1_THRESHOLD = 5;
    uint256 constant TIER2_THRESHOLD = 10;
    uint256 constant TIER3_THRESHOLD = 20;
    
    // Discount percentages (in basis points)
    uint256 constant TIER1_DISCOUNT = 500; // 5%
    uint256 constant TIER2_DISCOUNT = 1000; // 10%
    uint256 constant TIER3_DISCOUNT = 1500; // 15%
    
    // Events
    event OracleUpdated(uint256 oldOracleId, uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 accountId, uint256 newCount);

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
        oracleId = 1; // Default oracle ID
        
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
    function setOracleId(uint256 _oracleId) external onlyOwner {
        require(_oracleId > 0, "Invalid oracle ID");
        
        // Check if the new oracle exists and is active
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        require(value == bytes32(uint256(1)), "Oracle is not active");
        
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
        
        uint256 discountAmount = amount.mul(discountPercentage).div(10000);
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
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts are active
        require(_isAccountActive(sendAccountId), "Send account is not active");
        require(_isAccountActive(fromAccountId), "From account is not active");
        require(_isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(_hasEnoughBalance(fromAccountId, amount), "Insufficient balance");

        // Apply discount
        uint256 discountedAmount = _applyDiscount(sendAccountId, amount);

        // Execute transfer
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
        _incrementPurchaseCount(sendAccountId);

        emit CustomTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            miscValue1,
            miscValue2
        );

        return true;
    }

    // Internal functions

    function _isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Account lookup failed");
        return value == bytes32(uint256(1));
    }

    function _hasEnoughBalance(bytes32 accountId, uint256 amount) internal view returns (bool) {
        (bytes32 balanceValue, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Balance lookup failed");
        uint256 balance = uint256(balanceValue);
        return balance >= amount;
    }

    function _applyDiscount(bytes32 accountId, uint256 amount) internal returns (uint256) {
        uint256 purchasedCounts = purchaseCounts[accountId];
        uint256 discountedAmount = discount(amount, purchasedCounts);
        
        emit Discount(accountId, "PURCHASE", amount, discountedAmount);
        
        return discountedAmount;
    }

    function _incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
        emit PurchaseCountIncremented(accountId, purchaseCounts[accountId]);
    }

    // Admin functions

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Fallback and receive functions
    fallback() external payable {
        revert("Fallback not allowed");
    }

    receive() external payable {
        revert("Direct payments not allowed");
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
        require(sendAccountId != bytes32(0), "Send account ID cannot be empty");
        require(fromAccountId != bytes32(0), "From account ID cannot be empty");
        require(toAccountId != bytes32(0), "To account ID cannot be empty");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Trace ID cannot be empty");

        // Validate accounts
        require(_isAccountActive(sendAccountId), "Send account is not active");
        require(_isAccountActive(fromAccountId), "From account is not active");
        require(_isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(_getAccountBalance(fromAccountId) >= amount, "Insufficient balance in source account");

        // Get purchase history
        uint256 purchasedCounts = _getPurchaseHistory(sendAccountId);

        // Calculate discounted amount
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Execute transfer
        bool transferResult = _executeTransfer(fromAccountId, toAccountId, discountedAmount);
        require(transferResult, "Transfer failed");

        // Update purchase history
        _updatePurchaseHistory(sendAccountId);

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
    function _isAccountActive(bytes32 accountId) internal view returns (bool) {
        // Implementation depends on how accounts are stored and managed
        // This is a placeholder implementation
        return accountId != bytes32(0);
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function _getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        // Implementation depends on how balances are stored
        // This is a placeholder implementation
        return 1000000; // Assuming a large balance for demonstration
    }

    /**
     * @dev Gets the purchase history count for an account
     * @param accountId Account to check
     * @return uint256 Number of purchases
     */
    function _getPurchaseHistory(bytes32 accountId) internal view returns (uint256) {
        // Implementation depends on how purchase history is stored
        // This is a placeholder implementation
        return purchaseHistory[accountId];
    }

    /**
     * @dev Updates the purchase history for an account
     * @param accountId Account to update
     */
    function _updatePurchaseHistory(bytes32 accountId) internal {
        purchaseHistory[accountId] = purchaseHistory[accountId].add(1);
    }

    /**
     * @dev Executes a transfer between accounts
     * @param fromAccountId Source account
     * @param toAccountId Destination account
     * @param amount Amount to transfer
     * @return bool True if transfer was successful
     */
    function _executeTransfer(bytes32 fromAccountId, bytes32 toAccountId, uint256 amount) internal returns (bool) {
        // Implementation depends on how transfers are executed
        // This is a placeholder implementation
        return token.customTransfer(fromAccountId, fromAccountId, toAccountId, amount, bytes32(0), bytes32(0), "Discount transfer", bytes32(0));
    }

    /**
     * @dev Sets a new oracle ID for price feeds
     * @param newOracleId New oracle ID to use
     * @notice Only admin can update
     * @notice Validates oracle exists and is active
     */
    function setOracleId(uint256 newOracleId) external override onlyAdmin {
        require(newOracleId > 0, "Invalid oracle ID");
        require(_isOracleActive(newOracleId), "Oracle is not active");

        oracleId = newOracleId;
        emit OracleIdUpdated(newOracleId);
    }

    /**
     * @dev Checks if an oracle is active
     * @param oracleId Oracle ID to check
     * @return bool True if oracle is active
     */
    function _isOracleActive(uint256 oracleId) internal view returns (bool) {
        // Implementation depends on how oracles are managed
        // This is a placeholder implementation
        return oracleId > 0;
    }

    /**
     * @dev Gets the current oracle ID
     * @return uint256 Current oracle ID
     */
    function getOracleId() external view override returns (uint256) {
        return oracleId;
    }

    /**
     * @dev Returns the contract version
     * @return string Version in semver format
     */
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Initializes the contract with dependencies
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
        oracleId = 1; // Set default oracle ID
        admin = msg.sender;

        emit ContractInitialized(address(_oracle), address(_token));
    }

    /**
     * @dev Upgrades the contract to a new implementation
     * @param newImplementation Address of the new implementation
     * @notice Only admin can upgrade
     * @notice Validates new implementation address
     */
    function upgradeTo(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "Invalid implementation address");
        require(newImplementation != address(this), "Cannot upgrade to same implementation");

        _upgradeTo(newImplementation);
        emit ContractUpgraded(newImplementation);
    }

    /**
     * @dev Internal function to perform the upgrade
     * @param newImplementation Address of the new implementation
     */
    function _upgradeTo(address newImplementation) internal {
        // Store the new implementation address
        implementation = newImplementation;

        // Perform the upgrade
        (bool success, ) = newImplementation.delegatecall(
            abi.encodeWithSignature("initialize(address,address)", address(oracle), address(token))
        );
        require(success, "Upgrade failed");
    }

    /**
     * @dev Modifier to restrict access to admin only
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    /**
     * @dev Modifier to ensure initialization can only happen once
     */
    modifier initializer() {
        require(!initialized, "Contract is already initialized");
        initialized = true;
        _;
    }

    // Events
    event OracleIdUpdated(uint256 newOracleId);
    event ContractInitialized(address oracleAddress, address tokenAddress);
    event ContractUpgraded(address newImplementation);

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    address public admin;
    bool private initialized;
    address public implementation;
    mapping(bytes32 => uint256) private purchaseHistory;

    // Using SafeMath for uint256 operations
    using SafeMath for uint256;

// END PART 2

Here is PART 3 of the smart contract implementation:

// BEGIN PART 3

    /**
     * @dev Internal function to validate account IDs
     * @param accountId Account ID to validate
     */
    function _validateAccountId(bytes32 accountId) internal pure {
        require(accountId != bytes32(0), "Invalid account ID");
    }

    /**
     * @dev Internal function to validate amounts
     * @param amount Amount to validate
     */
    function _validateAmount(uint256 amount) internal pure {
        require(amount > 0, "Amount must be greater than zero");
    }

    /**
     * @dev Internal function to validate addresses
     * @param addr Address to validate
     */
    function _validateAddress(address addr) internal pure {
        require(addr != address(0), "Invalid address");
    }

    /**
     * @dev Internal function to check if an account exists and is active
     * @param accountId Account ID to check
     * @return bool True if account exists and is active
     */
    function _isAccountActive(bytes32 accountId) internal view returns (bool) {
        return accounts[accountId].isActive;
    }

    /**
     * @dev Internal function to check if an account has sufficient balance
     * @param accountId Account ID to check
     * @param amount Amount to check against
     * @return bool True if account has sufficient balance
     */
    function _hasSufficientBalance(bytes32 accountId, uint256 amount) internal view returns (bool) {
        return accounts[accountId].balance >= amount;
    }

    /**
     * @dev Internal function to update account balance
     * @param accountId Account ID to update
     * @param amount Amount to add (or subtract if negative)
     */
    function _updateBalance(bytes32 accountId, int256 amount) internal {
        if (amount > 0) {
            accounts[accountId].balance = accounts[accountId].balance.add(uint256(amount));
        } else {
            accounts[accountId].balance = accounts[accountId].balance.sub(uint256(-amount));
        }
    }

    /**
     * @dev Internal function to calculate tiered discount rate
     * @param purchasedCounts Number of previous purchases
     * @return Discount rate as a percentage (0-100)
     */
    function _calculateDiscountRate(uint256 purchasedCounts) internal pure returns (uint256) {
        if (purchasedCounts >= 100) {
            return 20; // 20% discount for 100+ purchases
        } else if (purchasedCounts >= 50) {
            return 15; // 15% discount for 50-99 purchases
        } else if (purchasedCounts >= 20) {
            return 10; // 10% discount for 20-49 purchases
        } else if (purchasedCounts >= 5) {
            return 5; // 5% discount for 5-19 purchases
        } else {
            return 0; // No discount for less than 5 purchases
        }
    }

    /**
     * @dev Internal function to apply discount to an amount
     * @param amount Original amount
     * @param discountRate Discount rate as a percentage (0-100)
     * @return Discounted amount
     */
    function _applyDiscount(uint256 amount, uint256 discountRate) internal pure returns (uint256) {
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to record a purchase for an account
     * @param accountId Account ID
     * @param item Item identifier
     * @param amount Purchase amount
     */
    function _recordPurchase(bytes32 accountId, bytes32 item, uint256 amount) internal {
        purchaseHistory[accountId].push(Purchase({
            item: item,
            amount: amount,
            timestamp: block.timestamp
        }));
    }

    /**
     * @dev Internal function to get the number of purchases for an account
     * @param accountId Account ID
     * @return Number of purchases
     */
    function _getPurchaseCount(bytes32 accountId) internal view returns (uint256) {
        return purchaseHistory[accountId].length;
    }

    /**
     * @dev Internal function to validate and process a custom transfer
     * @param sendAccountId Account initiating the transfer
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account
     * @param amount Number of tokens to transfer
     * @param miscValue1 First auxiliary parameter
     * @param miscValue2 Second auxiliary parameter
     * @param memo Transfer description/reason
     * @param traceId Unique identifier for tracking
     * @return True if transfer completed successfully
     */
    function _processCustomTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2,
        string memory memo,
        bytes32 traceId
    ) internal returns (bool) {
        _validateAccountId(sendAccountId);
        _validateAccountId(fromAccountId);
        _validateAccountId(toAccountId);
        _validateAmount(amount);

        require(_isAccountActive(sendAccountId), "Send account is not active");
        require(_isAccountActive(fromAccountId), "From account is not active");
        require(_isAccountActive(toAccountId), "To account is not active");
        require(_hasSufficientBalance(fromAccountId, amount), "Insufficient balance");

        _updateBalance(fromAccountId, -int256(amount));
        _updateBalance(toAccountId, int256(amount));

        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);

        // Record the transfer in transaction history
        transactionHistory.push(Transaction({
            sendAccountId: sendAccountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            amount: amount,
            miscValue1: miscValue1,
            miscValue2: miscValue2,
            memo: memo,
            traceId: traceId,
            timestamp: block.timestamp
        }));

        return true;
    }

    /**
     * @dev Internal function to fetch discount rate from oracle
     * @return Discount rate as a percentage (0-100)
     */
    function _fetchDiscountRateFromOracle() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Error fetching discount rate from oracle");
        return uint256(value);
    }

    /**
     * @dev Internal function to update the discount rate in the oracle
     * @param newRate New discount rate to set
     */
    function _updateDiscountRateInOracle(uint256 newRate) internal {
        require(newRate <= 100, "Invalid discount rate");
        oracle.set(oracleId, "DISCOUNT_RATE", bytes32(newRate));
    }

    /**
     * @dev Internal function to check if an address has admin privileges
     * @param addr Address to check
     * @return True if address has admin privileges
     */
    function _isAdmin(address addr) internal view returns (bool) {
        return adminRoles[addr];
    }

    /**
     * @dev Internal function to grant admin privileges to an address
     * @param addr Address to grant admin privileges
     */
    function _grantAdminRole(address addr) internal {
        adminRoles[addr] = true;
        emit AdminRoleGranted(addr);
    }

    /**
     * @dev Internal function to revoke admin privileges from an address
     * @param addr Address to revoke admin privileges
     */
    function _revokeAdminRole(address addr) internal {
        adminRoles[addr] = false;
        emit AdminRoleRevoked(addr);
    }

    /**
     * @dev Modifier to restrict access to admin only functions
     */
    modifier onlyAdmin() {
        require(_isAdmin(msg.sender), "Caller is not an admin");
        _;
    }

    /**
     * @dev Modifier to ensure the contract is not paused
     */
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * @dev Pause the contract
     * @notice Only callable by admin
     */
    function pause() external onlyAdmin {
        paused = true;
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpause the contract
     * @notice Only callable by admin
     */
    function unpause() external onlyAdmin {
        paused = false;
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @dev Upgrade the contract
     * @param newImplementation Address of the new implementation
     * @notice Only callable by admin
     */
    function upgradeContract(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "Invalid implementation address");
        _upgradeToAndCall(newImplementation, "", false);
        emit ContractUpgraded(newImplementation);
    }

    /**
     * @dev Emergency withdraw funds from the contract
     * @param amount Amount to withdraw
     * @param recipient Address to receive the funds
     * @notice Only callable by admin
     */
    function emergencyWithdraw(uint256 amount, address recipient) external onlyAdmin {
        require(recipient != address(0), "Invalid recipient address");
        require(address(this).balance >= amount, "Insufficient contract balance");
        payable(recipient).transfer(amount);
        emit EmergencyWithdrawal(recipient, amount);
    }

    /**
     * @dev Get the transaction history for an account
     * @param accountId Account ID to query
     * @return Array of transactions
     */
    function getTransactionHistory(bytes32 accountId) external view returns (Transaction[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < transactionHistory.length; i++) {
            if (transactionHistory[i].sendAccountId == accountId ||
                transactionHistory[i].fromAccountId == accountId ||
                transactionHistory[i].toAccountId == accountId) {
                count++;
            }
        }

        Transaction[] memory accountTransactions = new Transaction[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < transactionHistory.length; i++) {
            if (transactionHistory[i].sendAccountId == accountId ||
                transactionHistory[i].fromAccountId == accountId ||
                transactionHistory[i].toAccountId == accountId) {
                accountTransactions[index] = transactionHistory[i];
                index++;
            }
        }

        return accountTransactions;
    }

    /**
     * @dev Get the purchase history for an account
     * @param accountId Account ID to query
     * @return Array of purchases
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (Purchase[] memory) {
        return purchaseHistory[accountId];
    }

    /**
     * @dev Get the current discount rate
     * @return Current discount rate as a percentage (0-100)
     */
    function getCurrentDiscountRate() external view returns (uint256) {
        return _fetchDiscountRateFromOracle();
    }

    /**
     * @dev Set a new global discount rate
     * @param newRate New discount rate to set
     * @notice Only callable by admin
     */
    function setGlobalDiscountRate(uint256 newRate) external onlyAdmin {
        require(newRate <= 100, "Invalid discount rate");
        _updateDiscountRateInOracle(newRate);
        emit GlobalDiscountRateUpdated(newRate);
    }

    /**
     * @dev Apply a special discount to an account
     * @param accountId Account ID to apply the discount to
     * @param discountRate Special discount rate for this account
     * @notice Only callable by admin
     */
    function applySpecialDiscount(bytes32 accountId, uint256 discountRate) external onlyAdmin {
        require(discountRate <= 100, "Invalid discount rate");
        specialDiscounts[accountId] = discountRate;
        emit SpecialDiscountApplied(accountId, discountRate);
    }

    /**
     * @dev Remove a special discount from an account
     * @param accountId Account ID to remove the special discount from
     * @notice Only callable by admin
     */
    function removeSpecialDiscount(bytes32 accountId) external onlyAdmin {
        delete specialDiscounts[accountId];
        emit SpecialDiscountRemoved(accountId);
    }

    /**
     * @dev Get the special discount rate for an account
     * @param accountId Account ID to query
     * @return Special discount rate for the account (0 if not set)
     */
    function getSpecialDiscountRate(bytes32 accountId) external view returns (uint256) {
        return specialDiscounts[accountId];
    }

    /**
     * @dev Calculate the final discounted amount for a purchase
     * @param accountId Account ID making the purchase
     * @param amount Original purchase amount
     * @return Final discounted amount
     */
    function calculateDiscountedAmount(bytes32 accountId, uint256 amount) external view returns (uint256) {
        uint256 purchaseCount = _getPurchaseCount(accountId);
        uint256 baseDiscountRate = _calculateDiscountRate(purchaseCount);
        uint256 specialDiscountRate = specialDiscounts[accountId];
        uint256 globalDiscountRate = _fetchDiscountRateFromOracle();

        // Use the highest discount rate among base, special, and global
        uint256 effectiveDiscountRate = baseDiscountRate;
        if (specialDiscountRate > effectiveDiscountRate) {
            effectiveDiscountRate = specialDiscountRate;
        }
        if (globalDiscountRate > effectiveDiscountRate) {
            effectiveDiscountRate = globalDiscountRate;
        }

        return _applyDiscount(amount, effectiveDiscountRate);
    }

    /**
     * @dev Process a purchase with discount
     * @param accountId Account ID making the purchase
     * @param item Item identifier
     * @param amount Original purchase amount
     * @return Final discounted amount
     * @notice Updates purchase history and applies discount
     */
    function processPurchaseWithDiscount(bytes32 accountId, bytes32 item, uint256 amount) external whenNotPaused returns (uint256) {
        _validateAccountId(accountId);
        _validateAmount(amount);

        uint256 discountedAmount = this.calculateDiscountedAmount(accountId, amount);
        _recordPurchase(accountId, item, discountedAmount);

        emit Discount(accountId, item, amount, discountedAmount);

        return discountedAmount;
    }

    /**
     * @dev Get contract statistics
     * @return totalAccounts Total number of accounts
     * @return totalTransactions Total number of transactions
     * @return totalPurchases Total number of purchases
     */
    function getContractStatistics() external view returns (uint256 totalAccounts, uint256 totalTransactions, uint256 totalPurchases) {
        totalAccounts = accountCount;
        totalTransactions = transactionHistory.length;
        totalPurchases = 0;
        for (uint256 i = 0; i < accountCount; i++) {
            totalPurchases += purchaseHistory[bytes32(i)].length;
        }
    }

    /**
     * @dev Fallback function to receive Ether
     */
    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    /**
     * @dev Emitted when admin role is granted
     * @param account Address granted admin role
     */
    event AdminRoleGranted(address indexed account);

    /**
     * @dev Emitted when admin role is revoked
     * @param account Address revoked admin role
     */
    event AdminRoleRevoked(address indexed account);

    /**
     * @dev Emitted when contract is paused
     * @param account Address that paused the contract
     */
    event ContractPaused(address indexed account);

    /**
     * @dev Emitted when contract is unpaused
     * @param account Address that unpaused the