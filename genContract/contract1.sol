// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract Discount is IDiscount, Initializable, ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to track purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    // Discount percentages (in basis points)
    uint256 private constant TIER1_DISCOUNT = 500; // 5%
    uint256 private constant TIER2_DISCOUNT = 1000; // 10%
    uint256 private constant TIER3_DISCOUNT = 1500; // 15%
    
    // Events
    event OracleUpdated(uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 accountId, uint256 newCount);

    // Modifiers
    modifier onlyValidAccount(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    modifier onlyPositiveAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    /**
     * @dev Constructor is empty as contract uses initializer pattern
     */
    constructor() {
        _disableInitializers();
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
     */
    function setOracleId(uint256 _oracleId) external onlyOwner {
        require(_oracleId > 0, "Invalid oracle ID");
        
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
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
    function discount(uint256 amount, uint256 purchasedCounts) external pure onlyPositiveAmount(amount) returns (uint256) {
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
    ) external nonReentrant onlyValidAccount(sendAccountId) onlyValidAccount(fromAccountId) onlyValidAccount(toAccountId) onlyPositiveAmount(amount) returns (bool result) {
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Calculate discount
        uint256 purchaseCount = purchaseCounts[sendAccountId];
        uint256 discountedAmount = this.discount(amount, purchaseCount);

        // Execute transfer
        bool transferResult = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(transferResult, "Transfer failed");

        // Increment purchase count
        purchaseCounts[sendAccountId] = purchaseCount.add(1);
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
        (bytes32 value, string memory err) = oracle.get(oracleId, accountId);
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        return value == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        return uint256(value);
    }

    // Additional helper functions can be added here as needed

}

// END PART 1

// BEGIN PART 2

    /**
     * @dev Initializes discount contract with dependencies
     * @param oracle Oracle contract for price/discount data
     * @param token Token contract for payment handling
     * @notice Can only be called once during deployment
     * @notice Validates oracle and token addresses
     */
    function initialize(IOracle oracle, ITransferable token) external {
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
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Updates oracle instance used for discounts
     * @param oracleId New oracle ID to use
     * @notice Only admin can update
     * @notice Validates oracle exists and is active
     */
    function setOracleId(uint256 oracleId) external {
        require(msg.sender == admin, "Only admin can update oracle ID");
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
    function getOracleId() external view returns (uint256) {
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
    function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");

        uint256 discountPercentage;
        if (purchasedCounts >= 10) {
            discountPercentage = 10; // 10% discount for 10+ purchases
        } else if (purchasedCounts >= 5) {
            discountPercentage = 5; // 5% discount for 5-9 purchases
        } else if (purchasedCounts >= 1) {
            discountPercentage = 2; // 2% discount for 1-4 purchases
        } else {
            discountPercentage = 0; // No discount for first purchase
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        uint256 finalAmount = amount.sub(discountAmount);

        return finalAmount;
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
    ) external returns (bool result) {
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
        uint256 balance = getAccountBalance(fromAccountId);
        require(balance >= amount, "Insufficient balance in source account");

        // Perform transfer
        bool transferSuccess = tokenContract.customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            amount,
            miscValue1,
            miscValue2,
            memo,
            traceId
        );

        require(transferSuccess, "Transfer failed");

        // Apply discount if applicable
        uint256 purchasedCounts = getPurchaseCount(sendAccountId);
        uint256 discountedAmount = discount(amount, purchasedCounts);

        if (discountedAmount < amount) {
            // Refund the discount
            uint256 refundAmount = amount.sub(discountedAmount);
            bool refundSuccess = tokenContract.customTransfer(
                bytes32(uint256(address(this))),
                toAccountId,
                fromAccountId,
                refundAmount,
                bytes32("DISCOUNT_REFUND"),
                bytes32(0),
                "Discount refund",
                keccak256(abi.encodePacked(traceId, "REFUND"))
            );

            require(refundSuccess, "Discount refund failed");

            emit Discount(sendAccountId, miscValue1, amount, discountedAmount);
        }

        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);

        return true;
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account to check
     * @return bool True if account is active
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Account lookup failed");
        return value == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Balance lookup failed");
        return uint256(value);
    }

    /**
     * @dev Gets the purchase count for an account
     * @param accountId Account to check
     * @return uint256 Number of purchases
     */
    function getPurchaseCount(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("PURCHASE_COUNT", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Purchase count lookup failed");
        return uint256(value);
    }

    /**
     * @dev Updates the purchase count for an account
     * @param accountId Account to update
     * @param newCount New purchase count
     */
    function updatePurchaseCount(bytes32 accountId, uint256 newCount) internal {
        require(oracleContract.set(currentOracleId, keccak256(abi.encodePacked("PURCHASE_COUNT", accountId)), bytes32(newCount)), "Failed to update purchase count");
    }

    /**
     * @dev Applies a discount to a purchase
     * @param accountId Account making the purchase
     * @param itemId Item being purchased
     * @param amount Original purchase amount
     * @return uint256 Discounted amount
     */
    function applyDiscount(bytes32 accountId, bytes32 itemId, uint256 amount) internal returns (uint256) {
        uint256 purchaseCount = getPurchaseCount(accountId);
        uint256 discountedAmount = discount(amount, purchaseCount);

        // Update purchase count
        updatePurchaseCount(accountId, purchaseCount.add(1));

        emit Discount(accountId, itemId, amount, discountedAmount);
        return discountedAmount;
    }

    /**
     * @dev Processes a purchase with discount
     * @param buyerAccountId Account making the purchase
     * @param sellerAccountId Account receiving the payment
     * @param itemId Item being purchased
     * @param amount Purchase amount
     * @return bool True if purchase was successful
     */
    function processPurchase(bytes32 buyerAccountId, bytes32 sellerAccountId, bytes32 itemId, uint256 amount) external returns (bool) {
        require(buyerAccountId != bytes32(0), "Invalid buyer account");
        require(sellerAccountId != bytes32(0), "Invalid seller account");
        require(itemId != bytes32(0), "Invalid item ID");
        require(amount > 0, "Amount must be greater than 0");

        uint256 discountedAmount = applyDiscount(buyerAccountId, itemId, amount);

        bool transferSuccess = customTransfer(
            buyerAccountId,
            buyerAccountId,
            sellerAccountId,
            discountedAmount,
            itemId,
            bytes32(0),
            "Purchase with discount",
            keccak256(abi.encodePacked(buyerAccountId, sellerAccountId, itemId, block.timestamp))
        );

        require(transferSuccess, "Purchase transfer failed");

        emit PurchaseProcessed(buyerAccountId, sellerAccountId, itemId, amount, discountedAmount);
        return true;
    }

    /**
     * @dev Sets a new admin for the contract
     * @param newAdmin Address of the new admin
     * @notice Only current admin can call this function
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only current admin can set new admin");
        require(newAdmin != address(0), "Invalid new admin address");

        address oldAdmin = admin;
        admin = newAdmin;

        emit AdminChanged(oldAdmin, newAdmin);
    }

    /**
     * @dev Pauses all contract functions
     * @notice Only admin can call this function
     */
    function pause() external {
        require(msg.sender == admin, "Only admin can pause the contract");
        require(!paused, "Contract is already paused");

        paused = true;
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpauses all contract functions
     * @notice Only admin can call this function
     */
    function unpause() external {
        require(msg.sender == admin, "Only admin can unpause the contract");
        require(paused, "Contract is not paused");

        paused = false;
        emit ContractUnpaused(msg.sender);
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused
     */
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * @dev Emitted when the contract is paused
     * @param account Address that paused the contract
     */
    event ContractPaused(address account);

    /**
     * @dev Emitted when the contract is unpaused
     * @param account Address that unpaused the contract
     */
    event ContractUnpaused(address account);

    /**
     * @dev Emitted when a purchase is processed
     * @param buyerAccountId Account making the purchase
     * @param sellerAccountId Account receiving the payment
     * @param itemId Item being purchased
     * @param originalAmount Original purchase amount
     * @param discountedAmount Final amount after discount
     */
    event PurchaseProcessed(bytes32 buyerAccountId, bytes32 sellerAccountId, bytes32 itemId, uint256 originalAmount, uint256 discountedAmount);

    /**
     * @dev Emitted when the contract is initialized
     * @param oracleAddress Address of the oracle contract
     * @param tokenAddress Address of the token contract
     */
    event ContractInitialized(address oracleAddress, address tokenAddress);

    /**
     * @dev Emitted when the oracle ID is updated
     * @param newOracleId New oracle ID
     */
    event OracleIdUpdated(uint256 newOracleId);

    /**
     * @dev Emitted when the admin is changed
     * @param oldAdmin Address of the previous admin
     * @param newAdmin Address of the new admin
     */
    event AdminChanged(address oldAdmin, address newAdmin);

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
    function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");

        uint256 discountPercentage;
        if (purchasedCounts >= 20) {
            discountPercentage = 20; // 20% discount for 20+ purchases
        } else if (purchasedCounts >= 10) {
            discountPercentage = 15; // 15% discount for 10-19 purchases
        } else if (purchasedCounts >= 5) {
            discountPercentage = 10; // 10% discount for 5-9 purchases
        } else if (purchasedCounts >= 1) {
            discountPercentage = 5; // 5% discount for 1-4 purchases
        } else {
            return amount; // No discount for first-time buyers
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
     * @param item Identifier of the purchased item
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
     * @dev Helper function to get current discount rate from oracle
     * @return discountRate Current discount rate as a percentage
     */
    function _getCurrentDiscountRate() internal view returns (uint256 discountRate) {
        (bytes32 rateValue, string memory err) = oracle.get(currentOracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to fetch discount rate");
        discountRate = uint256(rateValue);
        require(discountRate <= 100, "Invalid discount rate");
        return discountRate;
    }

    /**
     * @dev Helper function to validate account exists and is active
     * @param accountId Account to validate
     */
    function _validateAccount(bytes32 accountId) internal view {
        require(accountId != bytes32(0), "Invalid account ID");
        // Additional logic to check if account exists and is active
        // This would typically involve querying a separate account management contract
        // or checking against a mapping of active accounts
    }

    /**
     * @dev Helper function to check if caller has admin privileges
     */
    function _onlyAdmin() internal view {
        require(msg.sender == admin, "Caller is not the admin");
    }

    /**
     * @dev Helper function to pause contract operations
     * @notice Only callable by admin
     */
    function pause() external {
        _onlyAdmin();
        _pause();
    }

    /**
     * @dev Helper function to unpause contract operations
     * @notice Only callable by admin
     */
    function unpause() external {
        _onlyAdmin();
        _unpause();
    }

    /**
     * @dev Helper function to upgrade the contract
     * @param newImplementation Address of the new implementation contract
     * @notice Only callable by admin
     */
    function upgradeContract(address newImplementation) external {
        _onlyAdmin();
        _upgradeToAndCall(newImplementation, "", false);
    }

    /**
     * @dev Helper function to withdraw any accidentally sent tokens
     * @param tokenAddress Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * @notice Only callable by admin
     */
    function withdrawToken(address tokenAddress, uint256 amount) external {
        _onlyAdmin();
        IERC20(tokenAddress).transfer(admin, amount);
    }

    /**
     * @dev Helper function to withdraw any accidentally sent Ether
     * @notice Only callable by admin
     */
    function withdrawEther() external {
        _onlyAdmin();
        payable(admin).transfer(address(this).balance);
    }

    /**
     * @dev Fallback function to handle incoming Ether
     */
    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    /**
     * @dev Emitted when Ether is received by the contract
     * @param sender Address that sent Ether
     * @param amount Amount of Ether received
     */
    event EtherReceived(address indexed sender, uint256 amount);

    // Additional helper functions and implementation details...

    // The contract would typically include more helper functions,
    // internal logic, and possibly additional features not explicitly
    // defined in the interface. These could include:

    // - Functions for batch operations
    // - Additional admin functions for contract management
    // - Extended logging and event emission
    // - Integration with other system components
    // - Specialized discount calculation algorithms
    // - Caching mechanisms for frequently accessed data
    // - Rate limiting or anti-abuse measures
    // - Emergency stop mechanisms
    // - Data migration functions for upgrades

    // The exact implementation would depend on the specific requirements
    // of the system and any additional features or constraints not
    // explicitly stated in the provided interface.
}

