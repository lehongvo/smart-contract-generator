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
    
    // Maximum discount percentage
    uint256 private constant MAX_DISCOUNT = 2000; // 20%
    
    // Minimum purchase amount for discount eligibility
    uint256 private constant MIN_PURCHASE_AMOUNT = 100; // 100 wei
    
    // Events
    event OracleUpdated(uint256 indexed oldOracleId, uint256 indexed newOracleId);
    event DiscountApplied(bytes32 indexed accountId, uint256 originalAmount, uint256 discountedAmount, uint256 discountPercentage);
    event PurchaseCountIncremented(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyInitialized() {
        require(address(oracle) != address(0) && address(token) != address(0), "Contract not initialized");
        _;
    }

    modifier validAccount(bytes32 accountId) {
        require(accountId != bytes32(0), "Invalid account ID");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    /**
     * @dev Constructor is empty as contract uses initializer pattern
     */
    constructor() {
        // Intentionally left empty
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

    // END PART 1

Here is PART 2 of the smart contract implementation:

// BEGIN PART 2

    using SafeMath for uint256;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;

    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount
    uint256 private constant MAX_DISCOUNT = 20; // 20% max discount

    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Mapping to store total purchase amounts for each account
    mapping(bytes32 => uint256) private totalPurchaseAmounts;

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

        if (purchasedCounts >= TIER3_THRESHOLD) {
            discountPercentage = TIER3_DISCOUNT;
        } else if (purchasedCounts >= TIER2_THRESHOLD) {
            discountPercentage = TIER2_DISCOUNT;
        } else if (purchasedCounts >= TIER1_THRESHOLD) {
            discountPercentage = TIER1_DISCOUNT;
        } else {
            discountPercentage = 0;
        }

        uint256 discountAmount = amount.mul(discountPercentage).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to apply discount to a purchase
     * @param sendAccountId Account making the purchase
     * @param item Identifier of the item being purchased
     * @param amount Original purchase amount
     * @return discountedAmount Final amount after applying discount
     */
    function applyDiscount(bytes32 sendAccountId, bytes32 item, uint256 amount) internal returns (uint256) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(item != bytes32(0), "Invalid item identifier");
        require(amount > 0, "Amount must be greater than zero");

        uint256 purchasedCounts = purchaseCounts[sendAccountId];
        uint256 discountedAmount = discount(amount, purchasedCounts);

        // Update purchase history
        purchaseCounts[sendAccountId] = purchasedCounts.add(1);
        totalPurchaseAmounts[sendAccountId] = totalPurchaseAmounts[sendAccountId].add(amount);

        emit Discount(sendAccountId, item, amount, discountedAmount);

        return discountedAmount;
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if purchase completed successfully
     */
    function executePurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(item != bytes32(0), "Invalid item identifier");

        uint256 discountedAmount = applyDiscount(sendAccountId, item, amount);

        result = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(0),
            memo,
            traceId
        );

        require(result, "Purchase transfer failed");

        return result;
    }

    /**
     * @dev Retrieves purchase history for an account
     * @param accountId Account to query
     * @return count Number of purchases made
     * @return totalAmount Total amount spent (before discounts)
     */
    function getPurchaseHistory(bytes32 accountId) external view returns (uint256 count, uint256 totalAmount) {
        require(accountId != bytes32(0), "Invalid accountId");

        count = purchaseCounts[accountId];
        totalAmount = totalPurchaseAmounts[accountId];
    }

    /**
     * @dev Calculates the current discount tier for an account
     * @param accountId Account to check
     * @return tier Current discount tier (0-3)
     * @return percentage Discount percentage for the current tier
     */
    function getCurrentDiscountTier(bytes32 accountId) external view returns (uint256 tier, uint256 percentage) {
        require(accountId != bytes32(0), "Invalid accountId");

        uint256 count = purchaseCounts[accountId];

        if (count >= TIER3_THRESHOLD) {
            tier = 3;
            percentage = TIER3_DISCOUNT;
        } else if (count >= TIER2_THRESHOLD) {
            tier = 2;
            percentage = TIER2_DISCOUNT;
        } else if (count >= TIER1_THRESHOLD) {
            tier = 1;
            percentage = TIER1_DISCOUNT;
        } else {
            tier = 0;
            percentage = 0;
        }
    }

    /**
     * @dev Calculates the number of purchases needed to reach the next discount tier
     * @param accountId Account to check
     * @return nextTier Next discount tier (1-3, or 0 if already at max)
     * @return purchasesNeeded Number of additional purchases needed
     */
    function getNextTierInfo(bytes32 accountId) external view returns (uint256 nextTier, uint256 purchasesNeeded) {
        require(accountId != bytes32(0), "Invalid accountId");

        uint256 count = purchaseCounts[accountId];

        if (count >= TIER3_THRESHOLD) {
            nextTier = 0; // Already at max tier
            purchasesNeeded = 0;
        } else if (count >= TIER2_THRESHOLD) {
            nextTier = 3;
            purchasesNeeded = TIER3_THRESHOLD.sub(count);
        } else if (count >= TIER1_THRESHOLD) {
            nextTier = 2;
            purchasesNeeded = TIER2_THRESHOLD.sub(count);
        } else {
            nextTier = 1;
            purchasesNeeded = TIER1_THRESHOLD.sub(count);
        }
    }

    /**
     * @dev Applies a one-time bonus discount to an account
     * @param accountId Account to receive the bonus
     * @param bonusPercentage Additional discount percentage (1-100)
     * @notice Only callable by admin
     */
    function applyBonusDiscount(bytes32 accountId, uint256 bonusPercentage) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(bonusPercentage > 0 && bonusPercentage <= 100, "Invalid bonus percentage");

        // Implementation details for bonus discount...
    }

    /**
     * @dev Resets purchase history for an account
     * @param accountId Account to reset
     * @notice Only callable by admin
     */
    function resetPurchaseHistory(bytes32 accountId) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");

        delete purchaseCounts[accountId];
        delete totalPurchaseAmounts[accountId];

        emit PurchaseHistoryReset(accountId);
    }

    /**
     * @dev Adjusts discount tiers and percentages
     * @param newTier1Threshold New threshold for Tier 1
     * @param newTier2Threshold New threshold for Tier 2
     * @param newTier3Threshold New threshold for Tier 3
     * @param newTier1Discount New discount percentage for Tier 1
     * @param newTier2Discount New discount percentage for Tier 2
     * @param newTier3Discount New discount percentage for Tier 3
     * @notice Only callable by admin
     */
    function adjustDiscountTiers(
        uint256 newTier1Threshold,
        uint256 newTier2Threshold,
        uint256 newTier3Threshold,
        uint256 newTier1Discount,
        uint256 newTier2Discount,
        uint256 newTier3Discount
    ) external onlyAdmin {
        require(newTier1Threshold < newTier2Threshold, "Invalid tier thresholds");
        require(newTier2Threshold < newTier3Threshold, "Invalid tier thresholds");
        require(newTier1Discount < newTier2Discount, "Invalid tier discounts");
        require(newTier2Discount < newTier3Discount, "Invalid tier discounts");
        require(newTier3Discount <= MAX_DISCOUNT, "Discount exceeds maximum allowed");

        // Implementation details for adjusting discount tiers...
    }

    /**
     * @dev Retrieves current discount tier information
     * @return tier1Threshold Current Tier 1 threshold
     * @return tier2Threshold Current Tier 2 threshold
     * @return tier3Threshold Current Tier 3 threshold
     * @return tier1Discount Current Tier 1 discount percentage
     * @return tier2Discount Current Tier 2 discount percentage
     * @return tier3Discount Current Tier 3 discount percentage
     */
    function getDiscountTierInfo() external view returns (
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint256 tier1Discount,
        uint256 tier2Discount,
        uint256 tier3Discount
    ) {
        tier1Threshold = TIER1_THRESHOLD;
        tier2Threshold = TIER2_THRESHOLD;
        tier3Threshold = TIER3_THRESHOLD;
        tier1Discount = TIER1_DISCOUNT;
        tier2Discount = TIER2_DISCOUNT;
        tier3Discount = TIER3_DISCOUNT;
    }

    /**
     * @dev Applies a temporary promotional discount
     * @param startTime Start time of the promotion
     * @param endTime End time of the promotion
     * @param promotionalDiscount Discount percentage for the promotion
     * @notice Only callable by admin
     */
    function setPromotionalDiscount(uint256 startTime, uint256 endTime, uint256 promotionalDiscount) external onlyAdmin {
        require(startTime < endTime, "Invalid promotion time range");
        require(promotionalDiscount > 0 && promotionalDiscount <= MAX_DISCOUNT, "Invalid promotional discount");

        // Implementation details for setting promotional discount...
    }

    /**
     * @dev Checks if a promotional discount is active
     * @return isActive True if a promotion is currently active
     * @return discountPercentage Current promotional discount percentage (0 if not active)
     */
    function checkPromotionalDiscount() external view returns (bool isActive, uint256 discountPercentage) {
        // Implementation details for checking promotional discount...
    }

    /**
     * @dev Applies an additional discount for bulk purchases
     * @param amount Original purchase amount
     * @param quantity Number of items in the bulk purchase
     * @return bulkDiscountedAmount Final amount after applying bulk discount
     */
    function applyBulkDiscount(uint256 amount, uint256 quantity) internal view returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");
        require(quantity > 0, "Quantity must be greater than zero");

        // Implementation details for bulk discount calculation...
    }

    /**
     * @dev Executes a bulk purchase with discounts applied
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the item being purchased
     * @param quantity Number of items in the bulk purchase
     * @param memo Description of the purchase
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if bulk purchase completed successfully
     */
    function executeBulkPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 quantity,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(item != bytes32(0), "Invalid item identifier");
        require(quantity > 0, "Quantity must be greater than zero");

        uint256 discountedAmount = applyDiscount(sendAccountId, item, amount);
        uint256 bulkDiscountedAmount = applyBulkDiscount(discountedAmount, quantity);

        result = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            bulkDiscountedAmount,
            item,
            bytes32(quantity),
            memo,
            traceId
        );

        require(result, "Bulk purchase transfer failed");

        emit BulkPurchase(sendAccountId, item, amount, bulkDiscountedAmount, quantity);

        return result;
    }

    /**
     * @dev Calculates potential savings for a future purchase
     * @param accountId Account to calculate for
     * @param amount Potential purchase amount
     * @return regularPrice Price without any discounts
     * @return discountedPrice Price after applying current discount tier
     * @return potentialSavings Amount that could be saved
     */
    function calculatePotentialSavings(bytes32 accountId, uint256 amount) external view returns (
        uint256 regularPrice,
        uint256 discountedPrice,
        uint256 potentialSavings
    ) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(amount > 0, "Amount must be greater than zero");

        regularPrice = amount;
        discountedPrice = discount(amount, purchaseCounts[accountId]);
        potentialSavings = regularPrice.sub(discountedPrice);
    }

    /**
     * @dev Retrieves discount statistics for an account
     * @param accountId Account to query
     * @return totalPurchases Total number of purchases made
     * @return totalSpent Total amount spent (before discounts)
     * @return totalSaved Total amount saved through discounts
     */
    function getDiscountStatistics(bytes32 accountId) external view returns (
        uint256 totalPurchases,
        uint256 totalSpent,
        uint256 totalSaved
    ) {
        require(accountId != bytes32(0), "Invalid accountId");

        totalPurchases = purchaseCounts[accountId];
        totalSpent = totalPurchaseAmounts[accountId];

        // Calculate total saved based on purchase history and discount tiers
        // Implementation details...
    }

    /**
     * @dev Applies a special one-time discount for a specific purchase
     * @param accountId Account

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
     */
    function _checkAccountActive(bytes32 accountId) internal view {
        require(_accounts[accountId].isActive, "Account is not active");
    }

    /**
     * @dev Internal function to check if an oracle exists
     * @param oracleId Oracle ID to check
     */
    function _checkOracleExists(uint256 oracleId) internal view {
        require(_oracles[oracleId].exists, "Oracle does not exist");
    }

    /**
     * @dev Internal function to apply tiered discount based on purchase history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases
     * @return discountedAmount Final discounted amount
     */
    function _applyTieredDiscount(uint256 amount, uint256 purchasedCounts) internal view returns (uint256 discountedAmount) {
        uint256 discountRate;
        
        if (purchasedCounts < 5) {
            discountRate = _getOracleValue("TIER1_DISCOUNT");
        } else if (purchasedCounts < 10) {
            discountRate = _getOracleValue("TIER2_DISCOUNT");
        } else if (purchasedCounts < 20) {
            discountRate = _getOracleValue("TIER3_DISCOUNT");
        } else {
            discountRate = _getOracleValue("TIER4_DISCOUNT");
        }

        uint256 discountAmount = amount.mul(discountRate).div(100);
        discountedAmount = amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to get oracle value
     * @param key Oracle data key
     * @return value Oracle data value
     */
    function _getOracleValue(bytes32 key) internal view returns (uint256 value) {
        (bytes32 rawValue, string memory err) = _oracle.get(_currentOracleId, key);
        require(bytes(err).length == 0, err);
        value = uint256(rawValue);
    }

    /**
     * @dev Internal function to update purchase history
     * @param accountId Account ID
     * @param item Purchased item
     */
    function _updatePurchaseHistory(bytes32 accountId, bytes32 item) internal {
        _purchaseHistory[accountId][item] = _purchaseHistory[accountId][item].add(1);
        _totalPurchases[accountId] = _totalPurchases[accountId].add(1);
    }

    /**
     * @dev Internal function to execute token transfer
     * @param fromAccountId Source account
     * @param toAccountId Destination account
     * @param amount Transfer amount
     */
    function _executeTransfer(bytes32 fromAccountId, bytes32 toAccountId, uint256 amount) internal {
        bool success = _token.customTransfer(
            fromAccountId,
            fromAccountId,
            toAccountId,
            amount,
            bytes32(0),
            bytes32(0),
            "Discount purchase",
            keccak256(abi.encodePacked(block.timestamp, fromAccountId, toAccountId, amount))
        );
        require(success, "Token transfer failed");
    }

    /**
     * @dev Upgrades the contract to a new implementation
     * @param newImplementation Address of the new implementation contract
     * @notice Only callable by the contract owner
     */
    function upgradeTo(address newImplementation) external onlyOwner {
        _validateAddress(newImplementation);
        require(newImplementation != address(this), "Cannot upgrade to same implementation");
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Emitted when the contract is upgraded to a new implementation
     * @param implementation Address of the new implementation
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Pauses all contract functions
     * @notice Only callable by the contract owner
     */
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Unpauses all contract functions
     * @notice Only callable by the contract owner
     */
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    /**
     * @dev Emitted when the contract is paused
     * @param account Address that paused the contract
     */
    event Paused(address account);

    /**
     * @dev Emitted when the contract is unpaused
     * @param account Address that unpaused the contract
     */
    event Unpaused(address account);

    /**
     * @dev Modifier to make a function callable only when the contract is not paused
     */
    modifier whenNotPaused() {
        require(!_paused, "Contract is paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only by the contract owner
     */
    modifier onlyOwner() {
        require(_msgSender() == _owner, "Caller is not the owner");
        _;
    }

    /**
     * @dev Returns the address of the current owner
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account
     * @param newOwner Address of the new owner
     * @notice Only callable by the current owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        _validateAddress(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /**
     * @dev Emitted when ownership is transferred
     * @param previousOwner Address of the previous owner
     * @param newOwner Address of the new owner
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Sets a new admin address for the contract
     * @param newAdmin Address of the new admin
     * @notice Only callable by the contract owner
     */
    function setAdmin(address newAdmin) external onlyOwner {
        _validateAddress(newAdmin);
        emit AdminChanged(_admin, newAdmin);
        _admin = newAdmin;
    }

    /**
     * @dev Emitted when the admin address is changed
     * @param previousAdmin Address of the previous admin
     * @param newAdmin Address of the new admin
     */
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

    /**
     * @dev Modifier to restrict access to admin functions
     */
    modifier onlyAdmin() {
        require(_msgSender() == _admin, "Caller is not the admin");
        _;
    }

    /**
     * @dev Internal function to get the current block timestamp
     * @return Current block timestamp
     */
    function _getBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Internal function to get the current block number
     * @return Current block number
     */
    function _getBlockNumber() internal view virtual returns (uint256) {
        return block.number;
    }

    /**
     * @dev Internal function to generate a unique identifier
     * @return Unique identifier
     */
    function _generateUniqueId() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(_getBlockTimestamp(), _getBlockNumber(), msg.sender));
    }

    /**
     * @dev Internal function to validate and process a purchase
     * @param accountId Account making the purchase
     * @param item Item being purchased
     * @param amount Original purchase amount
     * @return discountedAmount Final discounted amount
     */
    function _processPurchase(bytes32 accountId, bytes32 item, uint256 amount) internal returns (uint256 discountedAmount) {
        _validateAccountId(accountId);
        _validateAmount(amount);
        _checkAccountActive(accountId);

        uint256 purchasedCounts = _purchaseHistory[accountId][item];
        discountedAmount = discount(amount, purchasedCounts);

        _updatePurchaseHistory(accountId, item);
        _executeTransfer(accountId, _treasuryAccount, discountedAmount);

        emit Discount(accountId, item, amount, discountedAmount);
    }

    /**
     * @dev Internal function to batch update oracle values
     * @param oracleId Oracle ID
     * @param keys Array of data keys
     * @param values Array of data values
     */
    function _batchUpdateOracleValues(uint256 oracleId, bytes32[] memory keys, bytes32[] memory values) internal {
        require(keys.length == values.length, "Keys and values arrays must have the same length");
        for (uint256 i = 0; i < keys.length; i++) {
            _oracle.set(oracleId, keys[i], values[i]);
        }
    }

    /**
     * @dev Internal function to validate and update contract settings
     * @param settingName Name of the setting to update
     * @param settingValue New value for the setting
     */
    function _updateContractSetting(bytes32 settingName, bytes32 settingValue) internal {
        require(_contractSettings[settingName].exists, "Setting does not exist");
        require(_contractSettings[settingName].lastUpdated + _contractSettings[settingName].updateCooldown <= _getBlockTimestamp(), "Setting update is on cooldown");
        
        _contractSettings[settingName].value = settingValue;
        _contractSettings[settingName].lastUpdated = _getBlockTimestamp();
        
        emit ContractSettingUpdated(settingName, settingValue);
    }

    /**
     * @dev Emitted when a contract setting is updated
     * @param settingName Name of the updated setting
     * @param settingValue New value of the setting
     */
    event ContractSettingUpdated(bytes32 indexed settingName, bytes32 settingValue);

    /**
     * @dev Internal function to add a new contract setting
     * @param settingName Name of the new setting
     * @param initialValue Initial value for the setting
     * @param updateCooldown Cooldown period between updates
     * @notice Only callable by the contract owner
     */
    function _addContractSetting(bytes32 settingName, bytes32 initialValue, uint256 updateCooldown) internal onlyOwner {
        require(!_contractSettings[settingName].exists, "Setting already exists");
        
        _contractSettings[settingName] = ContractSetting({
            exists: true,
            value: initialValue,
            updateCooldown: updateCooldown,
            lastUpdated: _getBlockTimestamp()
        });
        
        emit ContractSettingAdded(settingName, initialValue, updateCooldown);
    }

    /**
     * @dev Emitted when a new contract setting is added
     * @param settingName Name of the new setting
     * @param initialValue Initial value of the setting
     * @param updateCooldown Cooldown period between updates
     */
    event ContractSettingAdded(bytes32 indexed settingName, bytes32 initialValue, uint256 updateCooldown);

    /**
     * @dev Internal function to remove a contract setting
     * @param settingName Name of the setting to remove
     * @notice Only callable by the contract owner
     */
    function _removeContractSetting(bytes32 settingName) internal onlyOwner {
        require(_contractSettings[settingName].exists, "Setting does not exist");
        
        delete _contractSettings[settingName];
        
        emit ContractSettingRemoved(settingName);
    }

    /**
     * @dev Emitted when a contract setting is removed
     * @param settingName Name of the removed setting
     */
    event ContractSettingRemoved(bytes32 indexed settingName);

    /**
     * @dev Internal function to get the value of a contract setting
     * @param settingName Name of the setting
     * @return value Current value of the setting
     */
    function _getContractSetting(bytes32 settingName) internal view returns (bytes32 value) {
        require(_contractSettings[settingName].exists, "Setting does not exist");
        return _contractSettings[settingName].value;
    }

    /**
     * @dev Internal function to validate and process a bulk discount
     * @param accountIds Array of account IDs
     * @param items Array of items being purchased
     * @param amounts Array of original purchase amounts
     * @return discountedAmounts Array of final discounted amounts
     */
    function _processBulkDiscount(bytes32[] memory accountIds, bytes32[] memory items, uint256[] memory amounts) internal returns (uint256[] memory discountedAmounts) {
        require(accountIds.length == items.length && items.length == amounts.length, "Input arrays must have the same length");
        
        discountedAmounts = new uint256[](amounts.length);
        
        for (uint256 i = 0; i < accountIds.length; i++) {
            discountedAmounts[i] = _processPurchase(accountIds[i], items[i], amounts[i]);
        }
    }

    /**
     * @dev Public function to process a bulk discount
     * @param accountIds Array of account IDs
     * @param items Array of items being purchased
     * @param amounts Array of original purchase amounts
     * @return discountedAmounts Array of final discounted amounts
     * @notice Only callable when the contract is not paused
     */
    function processBulkDiscount(bytes32[] memory accountIds, bytes32[] memory items, uint256[] memory amounts) public whenNotPaused returns (uint256[] memory discountedAmounts) {
        return _processBulkDiscount(accountIds, items, amounts);
    }

    /**
     * @dev Internal function to calculate the average discount for an account
     * @param accountId Account ID
     * @return averageDiscount Average discount percentage
     */
    function _calculateAverageDiscount(bytes32 accountId) internal view returns (uint256 averageDiscount) {
        uint256 totalDiscounts = 0;
        uint256 totalPurchases = _totalPurchases[accountId];
        
        if (totalPurchases == 0) {
            return 0;
        }
        
        for (uint256 i = 0; i < _purchaseHistory[accountId].length; i++) {
            totalDiscounts += _purchaseHistory[accountId][i];
        }
        
        averageDiscount = totalDiscounts.div(totalPurchases);
    }

    /**
     * @dev Public function to get the average discount for an account
     * @param accountId Account ID
     * @return Average discount percentage
     */
    function getAverageDiscount(bytes32 accountId) public view returns (uint256) {
        return _calculateAverageDiscount(accountId);
    }

    /**
     * @dev Internal function to apply a special promotion discount
     * @param amount Original purchase amount
     * @param promotionCode Promotion code to apply
     * @return discountedAmount Final discounted amount after applying the promotion
     */
    function _applyPromotionDiscount(uint256 amount, bytes32 promotionCode) internal view returns (uint256 discountedAmount) {
        require(_promotions[promotionCode].isActive, "Promotion is not active")