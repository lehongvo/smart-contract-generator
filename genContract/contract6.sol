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
    bool private initialized;

    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    uint256 private constant TIER1_DISCOUNT = 5; // 5%
    uint256 private constant TIER2_DISCOUNT = 10; // 10%
    uint256 private constant TIER3_DISCOUNT = 15; // 15%

    // Events
    event OracleUpdated(uint256 newOracleId);
    event PurchaseCountIncremented(bytes32 accountId, uint256 newCount);

    // Modifiers
    modifier onlyInitialized() {
        require(initialized, "Contract not initialized");
        _;
    }

    modifier validAddress(address _address) {
        require(_address != address(0), "Invalid address");
        _;
    }

    modifier validAmount(uint256 _amount) {
        require(_amount > 0, "Amount must be greater than zero");
        _;
    }

    modifier validAccountId(bytes32 _accountId) {
        require(_accountId != bytes32(0), "Invalid account ID");
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

    using SafeMath for uint256;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;

    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount

    // State variables
    IOracle private oracle;
    ITransferable private token;
    uint256 private oracleId;
    bool private initialized;

    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Admin address
    address private admin;

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    modifier onlyInitialized() {
        require(initialized, "Contract not initialized");
        _;
    }

    /**
     * @dev Initializes discount contract with dependencies
     * @param _oracle Oracle contract for price/discount data
     * @param _token Token contract for payment handling
     * @notice Can only be called once during deployment
     * @notice Validates oracle and token addresses
     */
    function initialize(IOracle _oracle, ITransferable _token) external override {
        require(!initialized, "Contract already initialized");
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");

        oracle = _oracle;
        token = _token;
        admin = msg.sender;
        initialized = true;
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
    function setOracleId(uint256 _oracleId) external override onlyAdmin onlyInitialized {
        require(_oracleId > 0, "Invalid oracle ID");
        
        // Check if the oracle exists and is active
        (bytes32 value, string memory err) = oracle.get(_oracleId, "ACTIVE");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle lookup failed");
        require(value == bytes32(uint256(1)), "Oracle is not active");

        oracleId = _oracleId;
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
    function discount(uint256 amount, uint256 purchasedCounts) external pure override returns (uint256) {
        require(amount > 0, "Purchase amount must be greater than 0");

        uint256 discountPercentage;

        if (purchasedCounts >= TIER3_THRESHOLD) {
            discountPercentage = TIER3_DISCOUNT;
        } else if (purchasedCounts >= TIER2_THRESHOLD) {
            discountPercentage = TIER2_DISCOUNT;
        } else if (purchasedCounts >= TIER1_THRESHOLD) {
            discountPercentage = TIER1_DISCOUNT;
        } else {
            return amount; // No discount applied
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
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
    ) external override onlyInitialized returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Get purchase count for the sender
        uint256 purchaseCount = purchaseCounts[sendAccountId];

        // Calculate discounted amount
        uint256 discountedAmount = this.discount(amount, purchaseCount);

        // Execute transfer with discounted amount
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

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Retrieves the purchase count for a given account
     * @param accountId The account to check
     * @return The number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) external view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Allows admin to reset purchase count for an account
     * @param accountId The account to reset
     * @notice Only admin can call this function
     */
    function resetPurchaseCount(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = 0;
    }

    /**
     * @dev Allows admin to set a custom purchase count for an account
     * @param accountId The account to update
     * @param count The new purchase count
     * @notice Only admin can call this function
     */
    function setPurchaseCount(bytes32 accountId, uint256 count) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = count;
    }

    /**
     * @dev Allows admin to transfer ownership of the contract
     * @param newAdmin Address of the new admin
     * @notice Only current admin can call this function
     */
    function transferAdminship(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid new admin address");
        admin = newAdmin;
    }

    /**
     * @dev Retrieves the current admin address
     * @return The address of the current admin
     */
    function getAdmin() external view returns (address) {
        return admin;
    }

    /**
     * @dev Allows admin to pause the contract in case of emergency
     * @notice Only admin can call this function
     */
    bool private paused;

    function pauseContract() external onlyAdmin {
        paused = true;
    }

    /**
     * @dev Allows admin to unpause the contract
     * @notice Only admin can call this function
     */
    function unpauseContract() external onlyAdmin {
        paused = false;
    }

    /**
     * @dev Checks if the contract is paused
     * @return True if the contract is paused, false otherwise
     */
    function isPaused() external view returns (bool) {
        return paused;
    }

    /**
     * @dev Allows admin to update the oracle contract address
     * @param newOracle Address of the new oracle contract
     * @notice Only admin can call this function
     */
    function updateOracleContract(IOracle newOracle) external onlyAdmin {
        require(address(newOracle) != address(0), "Invalid new oracle address");
        oracle = newOracle;
    }

    /**
     * @dev Allows admin to update the token contract address
     * @param newToken Address of the new token contract
     * @notice Only admin can call this function
     */
    function updateTokenContract(ITransferable newToken) external onlyAdmin {
        require(address(newToken) != address(0), "Invalid new token address");
        token = newToken;
    }

    /**
     * @dev Retrieves the current oracle contract address
     * @return The address of the current oracle contract
     */
    function getOracleContract() external view returns (address) {
        return address(oracle);
    }

    /**
     * @dev Retrieves the current token contract address
     * @return The address of the current token contract
     */
    function getTokenContract() external view returns (address) {
        return address(token);
    }

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
     * @dev Internal function to check if an oracle exists
     * @param oracleId Oracle ID to check
     */
    function _validateOracleExists(uint256 oracleId) internal view {
        require(oracleId > 0 && oracleId <= oracleCount, "Oracle does not exist");
    }

    /**
     * @dev Internal function to check if an invoker is authorized for an oracle
     * @param oracleId Oracle ID to check
     * @param invoker Address to validate
     */
    function _validateOracleInvoker(uint256 oracleId, address invoker) internal view {
        require(oracles[oracleId].invoker == invoker, "Unauthorized invoker");
    }

    /**
     * @dev Internal function to get a discount rate based on purchase history
     * @param purchasedCounts Number of previous purchases
     * @return Discount rate as a percentage (0-100)
     */
    function _getDiscountRate(uint256 purchasedCounts) internal pure returns (uint256) {
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
     * @dev Internal function to apply a discount to an amount
     * @param amount Original amount
     * @param discountRate Discount rate as a percentage (0-100)
     * @return Discounted amount
     */
    function _applyDiscount(uint256 amount, uint256 discountRate) internal pure returns (uint256) {
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to update purchase history
     * @param accountId Account ID to update
     */
    function _updatePurchaseHistory(bytes32 accountId) internal {
        purchaseHistory[accountId] = purchaseHistory[accountId].add(1);
    }

    /**
     * @dev Internal function to get the current discount rate from the oracle
     * @return Current discount rate as a percentage (0-100)
     */
    function _getCurrentDiscountRate() internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(currentOracleId, "DISCOUNT_RATE");
        require(bytes(err).length == 0, "Failed to get discount rate from oracle");
        return uint256(value);
    }

    /**
     * @dev Internal function to get the current item price from the oracle
     * @param item Item identifier
     * @return Current price of the item
     */
    function _getItemPrice(bytes32 item) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(currentOracleId, item);
        require(bytes(err).length == 0, "Failed to get item price from oracle");
        return uint256(value);
    }

    /**
     * @dev Internal function to execute a transfer using the token contract
     * @param fromAccountId Source account
     * @param toAccountId Destination account
     * @param amount Amount to transfer
     * @param memo Transfer memo
     * @return True if transfer was successful
     */
    function _executeTransfer(
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        string memory memo
    ) internal returns (bool) {
        return token.customTransfer(
            fromAccountId,
            fromAccountId,
            toAccountId,
            amount,
            bytes32(0),
            bytes32(0),
            memo,
            keccak256(abi.encodePacked(block.timestamp, fromAccountId, toAccountId, amount))
        );
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
        _validateAmount(amount);
        uint256 discountRate = _getDiscountRate(purchasedCounts);
        return _applyDiscount(amount, discountRate);
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param accountId Account making the purchase
     * @param item Item being purchased
     * @return Final discounted amount charged
     */
    function purchaseWithDiscount(bytes32 accountId, bytes32 item) external returns (uint256) {
        _validateAccountId(accountId);
        uint256 itemPrice = _getItemPrice(item);
        uint256 purchasedCounts = purchaseHistory[accountId];
        uint256 discountedAmount = discount(itemPrice, purchasedCounts);
        
        require(_executeTransfer(accountId, treasury, discountedAmount, "Discounted purchase"), "Transfer failed");
        
        _updatePurchaseHistory(accountId);
        
        emit Discount(accountId, item, itemPrice, discountedAmount);
        
        return discountedAmount;
    }

    /**
     * @dev Admin function to update discount tiers
     * @param newTiers Array of new discount tiers
     * @param newRates Array of new discount rates corresponding to tiers
     * @notice Only callable by admin
     * @notice Arrays must be of equal length
     */
    function updateDiscountTiers(uint256[] memory newTiers, uint256[] memory newRates) external onlyAdmin {
        require(newTiers.length == newRates.length, "Mismatched array lengths");
        require(newTiers.length > 0, "Empty arrays not allowed");
        
        delete discountTiers;
        delete discountRates;
        
        for (uint256 i = 0; i < newTiers.length; i++) {
            discountTiers.push(newTiers[i]);
            discountRates.push(newRates[i]);
        }
        
        emit DiscountTiersUpdated(newTiers, newRates);
    }

    /**
     * @dev Admin function to set the treasury account
     * @param newTreasury New treasury account ID
     * @notice Only callable by admin
     */
    function setTreasury(bytes32 newTreasury) external onlyAdmin {
        _validateAccountId(newTreasury);
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /**
     * @dev Allows admin to pause the contract in case of emergency
     * @notice Only callable by admin
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev Allows admin to unpause the contract
     * @notice Only callable by admin
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    /**
     * @dev Fallback function to reject any accidental Ether sent to the contract
     */
    receive() external payable {
        revert("Contract does not accept Ether");
    }

    /**
     * @dev Emitted when discount tiers are updated
     * @param newTiers New array of discount tiers
     * @param newRates New array of discount rates
     */
    event DiscountTiersUpdated(uint256[] newTiers, uint256[] newRates);

    /**
     * @dev Emitted when treasury account is updated
     * @param newTreasury New treasury account ID
     */
    event TreasuryUpdated(bytes32 newTreasury);
}