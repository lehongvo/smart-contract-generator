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
    
    // Discount percentages (in basis points)
    uint256 private constant TIER1_DISCOUNT = 500; // 5%
    uint256 private constant TIER2_DISCOUNT = 1000; // 10%
    uint256 private constant TIER3_DISCOUNT = 1500; // 15%
    
    // Maximum discount percentage
    uint256 private constant MAX_DISCOUNT = 2000; // 20%
    
    // Events
    event OracleUpdated(uint256 oldOracleId, uint256 newOracleId);
    event PurchaseCountIncreased(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyInitialized() {
        require(address(oracle) != address(0) && address(token) != address(0), "Contract not initialized");
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
        
        // Transfer ownership to the deployer
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
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        require(value == bytes32(uint256(1)), "Oracle not active");
        
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
        
        // Apply discount
        uint256 discountAmount = amount.mul(discountPercentage).div(10000);
        
        // Ensure discount doesn't exceed maximum
        uint256 maxDiscountAmount = amount.mul(MAX_DISCOUNT).div(10000);
        discountAmount = discountAmount > maxDiscountAmount ? maxDiscountAmount : discountAmount;
        
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
        require(sendAccountId != bytes32(0), "Invalid send account ID");
        require(fromAccountId != bytes32(0), "Invalid from account ID");
        require(toAccountId != bytes32(0), "Invalid to account ID");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Apply discount
        uint256 discountedAmount = applyDiscount(sendAccountId, amount);

        // Execute transfer
        bool transferResult = token.customTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2, memo, traceId);
        require(transferResult, "Transfer failed");

        // Increase purchase count
        increasePurchaseCount(sendAccountId);

        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    // Internal helper functions

    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_ACTIVE_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return value == bytes32(uint256(1));
    }

    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("ACCOUNT_BALANCE_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return uint256(value);
    }

    function applyDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        uint256 purchasedCounts = purchaseCounts[accountId];
        return discount(amount, purchasedCounts);
    }

    function increasePurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
        emit PurchaseCountIncreased(accountId, purchaseCounts[accountId]);
    }

    // Additional helper functions for extensibility

    function getAccountPurchaseCount(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        return purchaseCounts[accountId];
    }

    function resetAccountPurchaseCount(bytes32 accountId) external onlyOwner validAccountId(accountId) {
        purchaseCounts[accountId] = 0;
        emit PurchaseCountIncreased(accountId, 0);
    }

    function bulkResetPurchaseCounts(bytes32[] memory accountIds) external onlyOwner {
        for (uint256 i = 0; i < accountIds.length; i++) {
            require(accountIds[i] != bytes32(0), "Invalid account ID");
            purchaseCounts[accountIds[i]] = 0;
            emit PurchaseCountIncreased(accountIds[i], 0);
        }
    }

    function setCustomDiscount(bytes32 accountId, uint256 discountPercentage) external onlyOwner validAccountId(accountId) {
        require(discountPercentage <= MAX_DISCOUNT, "Discount exceeds maximum allowed");
        oracle.set(oracleId, keccak256(abi.encodePacked("CUSTOM_DISCOUNT_", accountId)), bytes32(discountPercentage));
    }

    function getCustomDiscount(bytes32 accountId) external view validAccountId(accountId) returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("CUSTOM_DISCOUNT_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return uint256(value);
    }

    function applyCustomDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        (bytes32 customDiscountValue, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("CUSTOM_DISCOUNT_", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        
        uint256 customDiscountPercentage = uint256(customDiscountValue);
        if (customDiscountPercentage > 0) {
            uint256 discountAmount = amount.mul(customDiscountPercentage).div(10000);
            return amount.sub(discountAmount);
        }
        
        return amount;
    }

    function setDiscountTier(uint256 tier, uint256 threshold, uint256 discountPercentage) external onlyOwner {
        require(tier > 0 && tier <= 3, "Invalid tier");
        require(threshold > 0, "Invalid threshold");
        require(discountPercentage <= MAX_DISCOUNT, "Discount exceeds maximum allowed");
        
        bytes32 thresholdKey = keccak256(abi.encodePacked("TIER_THRESHOLD_", tier));
        bytes32 discountKey = keccak256(abi.encodePacked("TIER_DISCOUNT_", tier));
        
        oracle.set(oracleId, thresholdKey, bytes32(threshold));
        oracle.set(oracleId, discountKey, bytes32(discountPercentage));
    }

    function getDiscountTier(uint256 tier) external view returns (uint256 threshold, uint256 discountPercentage) {
        require(tier > 0 && tier <= 3, "Invalid tier");
        
        bytes32 thresholdKey = keccak256(abi.encodePacked("TIER_THRESHOLD_", tier));
        bytes32 discountKey = keccak256(abi.encodePacked("TIER_DISCOUNT_", tier));
        
        (bytes32 thresholdValue, string memory err1) = oracle.get(oracleId, thresholdKey);
        require(keccak256(abi.encodePacked(err1)) == keccak256(abi.encodePacked("")), "Oracle error");
        
        (bytes32 discountValue, string memory err2) = oracle.get(oracleId, discountKey);
        require(keccak256(abi.encodePacked(err2)) == keccak256(abi.encodePacked("")), "Oracle error");
        
        return (uint256(thresholdValue), uint256(discountValue));
    }

    function setMaxDiscount(uint256 newMaxDiscount) external onlyOwner {
        require(newMaxDiscount <= 5000, "Max discount cannot exceed 50%");
        oracle.set(oracleId, "MAX_DISCOUNT", bytes32(newMaxDiscount));
    }

    function getMaxDiscount() external view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "MAX_DISCOUNT");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return uint256(value);
    }

    // Emergency functions

    function pause() external onlyOwner {
        oracle.set(oracleId, "PAUSED", bytes32(uint256(1)));
    }

    function unpause() external onlyOwner {
        oracle.set(oracleId, "PAUSED", bytes32(uint256(0)));
    }

    function isPaused() public view returns (bool) {
        (bytes32 value, string memory err) = oracle.get(oracleId, "PAUSED");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Oracle error");
        return value == bytes32(uint256(1));
    }

    modifier whenNotPaused() {
        require(!isPaused(), "Contract is paused");
        _;
    }

    // Override transfer function to include pause check
    function customTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2,
        string memory memo,
        bytes32 traceId
    ) external override whenNotPaused returns (bool result) {
        return super.customTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2, memo, traceId);
    }

    // Upgrade functions

    function prepareUpgrade(address newImplementation) external onlyOwner {
        // Perform any necessary state migrations or validations before upgrading
        

Here's PART 2 of the smart contract implementation for the Discount contract:

// BEGIN PART 2

    using SafeMath for uint256;

    // Discount tiers
    struct DiscountTier {
        uint256 minPurchases;
        uint256 discountRate; // In basis points (1/100 of a percent)
    }

    // Mapping to store discount tiers
    mapping(uint256 => DiscountTier) public discountTiers;

    // Number of discount tiers
    uint256 public tiersCount;

    // Mapping to store user purchase counts
    mapping(bytes32 => uint256) public userPurchaseCounts;

    // Maximum discount rate allowed (in basis points)
    uint256 public constant MAX_DISCOUNT_RATE = 5000; // 50%

    // Minimum purchase amount for discount eligibility
    uint256 public minPurchaseAmount;

    /**
     * @dev Initializes the discount tiers
     * @notice This function should be called only once after contract deployment
     */
    function initializeDiscountTiers() internal {
        require(tiersCount == 0, "Discount tiers already initialized");

        discountTiers[1] = DiscountTier(0, 0); // No discount for new users
        discountTiers[2] = DiscountTier(5, 500); // 5% discount after 5 purchases
        discountTiers[3] = DiscountTier(10, 1000); // 10% discount after 10 purchases
        discountTiers[4] = DiscountTier(20, 1500); // 15% discount after 20 purchases
        discountTiers[5] = DiscountTier(50, 2000); // 20% discount after 50 purchases

        tiersCount = 5;
        minPurchaseAmount = 100 * 10**18; // 100 tokens as minimum purchase amount
    }

    /**
     * @dev Updates a specific discount tier
     * @param tierId The ID of the tier to update
     * @param minPurchases Minimum number of purchases required for this tier
     * @param discountRate Discount rate for this tier (in basis points)
     * @notice Only callable by admin
     */
    function updateDiscountTier(uint256 tierId, uint256 minPurchases, uint256 discountRate) external onlyAdmin {
        require(tierId > 0 && tierId <= tiersCount, "Invalid tier ID");
        require(discountRate <= MAX_DISCOUNT_RATE, "Discount rate too high");

        discountTiers[tierId] = DiscountTier(minPurchases, discountRate);

        emit DiscountTierUpdated(tierId, minPurchases, discountRate);
    }

    /**
     * @dev Adds a new discount tier
     * @param minPurchases Minimum number of purchases required for this tier
     * @param discountRate Discount rate for this tier (in basis points)
     * @notice Only callable by admin
     */
    function addDiscountTier(uint256 minPurchases, uint256 discountRate) external onlyAdmin {
        require(discountRate <= MAX_DISCOUNT_RATE, "Discount rate too high");

        tiersCount = tiersCount.add(1);
        discountTiers[tiersCount] = DiscountTier(minPurchases, discountRate);

        emit DiscountTierAdded(tiersCount, minPurchases, discountRate);
    }

    /**
     * @dev Removes the last discount tier
     * @notice Only callable by admin
     */
    function removeLastDiscountTier() external onlyAdmin {
        require(tiersCount > 1, "Cannot remove all tiers");

        delete discountTiers[tiersCount];
        tiersCount = tiersCount.sub(1);

        emit DiscountTierRemoved(tiersCount.add(1));
    }

    /**
     * @dev Sets the minimum purchase amount for discount eligibility
     * @param amount New minimum purchase amount
     * @notice Only callable by admin
     */
    function setMinPurchaseAmount(uint256 amount) external onlyAdmin {
        require(amount > 0, "Minimum purchase amount must be greater than zero");
        minPurchaseAmount = amount;

        emit MinPurchaseAmountUpdated(amount);
    }

    /**
     * @dev Calculates discount based on purchase amount and history
     * @param amount Original purchase amount
     * @param purchasedCounts Number of previous purchases by account
     * @return Final discounted amount to charge
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) public view override returns (uint256) {
        require(amount > 0, "Purchase amount must be greater than zero");

        if (amount < minPurchaseAmount) {
            return amount; // No discount for purchases below minimum amount
        }

        uint256 discountRate = 0;
        for (uint256 i = 1; i <= tiersCount; i++) {
            if (purchasedCounts >= discountTiers[i].minPurchases) {
                discountRate = discountTiers[i].discountRate;
            } else {
                break;
            }
        }

        uint256 discountAmount = amount.mul(discountRate).div(10000);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param sendAccountId Account making the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually the merchant)
     * @param amount Original purchase amount
     * @param itemId Identifier of the purchased item
     * @param memo Human readable purchase description
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if purchase completed successfully
     * @notice Validates all accounts exist and are active
     * @notice Applies discount based on user's purchase history
     * @notice Updates user's purchase count after successful transaction
     */
    function purchaseWithDiscount(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 itemId,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid send account");
        require(fromAccountId != bytes32(0), "Invalid from account");
        require(toAccountId != bytes32(0), "Invalid to account");
        require(amount > 0, "Amount must be greater than zero");

        uint256 purchasedCounts = userPurchaseCounts[sendAccountId];
        uint256 discountedAmount = discount(amount, purchasedCounts);

        result = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            itemId,
            bytes32(0),
            memo,
            traceId
        );

        if (result) {
            userPurchaseCounts[sendAccountId] = purchasedCounts.add(1);
            emit Discount(sendAccountId, itemId, amount, discountedAmount);
        }

        return result;
    }

    /**
     * @dev Retrieves the current discount rate for a given account
     * @param accountId The account to check
     * @return discountRate The current discount rate in basis points
     */
    function getCurrentDiscountRate(bytes32 accountId) external view returns (uint256 discountRate) {
        uint256 purchasedCounts = userPurchaseCounts[accountId];
        
        for (uint256 i = 1; i <= tiersCount; i++) {
            if (purchasedCounts >= discountTiers[i].minPurchases) {
                discountRate = discountTiers[i].discountRate;
            } else {
                break;
            }
        }

        return discountRate;
    }

    /**
     * @dev Retrieves the purchase count for a given account
     * @param accountId The account to check
     * @return count The number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) external view returns (uint256 count) {
        return userPurchaseCounts[accountId];
    }

    /**
     * @dev Manually updates the purchase count for an account (for migration or correction purposes)
     * @param accountId The account to update
     * @param newCount The new purchase count to set
     * @notice Only callable by admin
     */
    function updatePurchaseCount(bytes32 accountId, uint256 newCount) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid account");
        userPurchaseCounts[accountId] = newCount;

        emit PurchaseCountUpdated(accountId, newCount);
    }

    /**
     * @dev Retrieves details of a specific discount tier
     * @param tierId The ID of the tier to query
     * @return minPurchases Minimum number of purchases required for this tier
     * @return discountRate Discount rate for this tier (in basis points)
     */
    function getDiscountTier(uint256 tierId) external view returns (uint256 minPurchases, uint256 discountRate) {
        require(tierId > 0 && tierId <= tiersCount, "Invalid tier ID");
        DiscountTier memory tier = discountTiers[tierId];
        return (tier.minPurchases, tier.discountRate);
    }

    /**
     * @dev Calculates the next discount tier for a given account
     * @param accountId The account to check
     * @return nextTierId The ID of the next discount tier
     * @return nextMinPurchases The number of purchases required to reach the next tier
     * @return nextDiscountRate The discount rate of the next tier
     */
    function getNextDiscountTier(bytes32 accountId) external view returns (
        uint256 nextTierId,
        uint256 nextMinPurchases,
        uint256 nextDiscountRate
    ) {
        uint256 purchasedCounts = userPurchaseCounts[accountId];
        
        for (uint256 i = 1; i <= tiersCount; i++) {
            if (purchasedCounts < discountTiers[i].minPurchases) {
                return (i, discountTiers[i].minPurchases, discountTiers[i].discountRate);
            }
        }

        // If the account is already at the highest tier
        return (0, 0, 0);
    }

    /**
     * @dev Calculates potential savings for a given purchase amount
     * @param amount The purchase amount to calculate savings for
     * @param accountId The account making the purchase
     * @return originalAmount The original purchase amount
     * @return discountedAmount The amount after applying the discount
     * @return savings The total savings
     */
    function calculatePotentialSavings(uint256 amount, bytes32 accountId) external view returns (
        uint256 originalAmount,
        uint256 discountedAmount,
        uint256 savings
    ) {
        require(amount > 0, "Amount must be greater than zero");
        uint256 purchasedCounts = userPurchaseCounts[accountId];
        
        originalAmount = amount;
        discountedAmount = discount(amount, purchasedCounts);
        savings = originalAmount.sub(discountedAmount);

        return (originalAmount, discountedAmount, savings);
    }

    // Events
    event DiscountTierUpdated(uint256 indexed tierId, uint256 minPurchases, uint256 discountRate);
    event DiscountTierAdded(uint256 indexed tierId, uint256 minPurchases, uint256 discountRate);
    event DiscountTierRemoved(uint256 indexed tierId);
    event MinPurchaseAmountUpdated(uint256 newAmount);
    event PurchaseCountUpdated(bytes32 indexed accountId, uint256 newCount);

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
    function discount(uint256 amount, uint256 purchasedCounts) public pure override returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");

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
     * @return bool True if the discounted transfer was successful
     */
    function applyDiscountAndTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        uint256 purchasedCounts
    ) internal returns (bool) {
        uint256 discountedAmount = discount(amount, purchasedCounts);

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(purchasedCounts),
            string(abi.encodePacked("Discounted purchase of ", item)),
            keccak256(abi.encodePacked(sendAccountId, fromAccountId, toAccountId, discountedAmount, item, block.timestamp))
        );

        if (transferResult) {
            emit Discount(sendAccountId, item, amount, discountedAmount);
        }

        return transferResult;
    }

    /**
     * @dev Executes a discounted purchase
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the purchased item
     * @return bool True if the discounted purchase was successful
     */
    function executePurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(item != bytes32(0), "Invalid item identifier");

        uint256 purchasedCounts = getPurchaseCount(sendAccountId);
        bool result = applyDiscountAndTransfer(sendAccountId, fromAccountId, toAccountId, amount, item, purchasedCounts);

        if (result) {
            incrementPurchaseCount(sendAccountId);
        }

        return result;
    }

    /**
     * @dev Retrieves the purchase count for a given account
     * @param accountId The account to check
     * @return uint256 The number of purchases made by the account
     */
    function getPurchaseCount(bytes32 accountId) public view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Increments the purchase count for a given account
     * @param accountId The account to increment the count for
     */
    function incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchaseCount The number of previous purchases
     * @return uint256 The discount percentage (0-100)
     */
    function getDiscountRate(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount == 0) {
            return 0;
        } else if (purchaseCount < 5) {
            return 5;
        } else if (purchaseCount < 10) {
            return 10;
        } else if (purchaseCount < 20) {
            return 15;
        } else {
            return 20;
        }
    }

    /**
     * @dev Allows admin to set a custom discount rate for a specific account
     * @param accountId The account to set the custom rate for
     * @param rate The custom discount rate (0-100)
     */
    function setCustomDiscountRate(bytes32 accountId, uint256 rate) external onlyAdmin {
        require(accountId != bytes32(0), "Invalid accountId");
        require(rate <= 100, "Invalid discount rate");
        customDiscountRates[accountId] = rate;
        emit CustomDiscountRateSet(accountId, rate);
    }

    /**
     * @dev Retrieves the custom discount rate for a specific account
     * @param accountId The account to check
     * @return uint256 The custom discount rate, or 0 if not set
     */
    function getCustomDiscountRate(bytes32 accountId) public view returns (uint256) {
        return customDiscountRates[accountId];
    }

    /**
     * @dev Calculates the discounted amount using custom rates if available
     * @param amount The original amount
     * @param accountId The account making the purchase
     * @return uint256 The discounted amount
     */
    function calculateDiscountedAmount(uint256 amount, bytes32 accountId) public view returns (uint256) {
        uint256 discountRate = getCustomDiscountRate(accountId);
        if (discountRate == 0) {
            discountRate = getDiscountRate(getPurchaseCount(accountId));
        }
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Executes a bulk purchase with discounts for multiple items
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amounts Array of original purchase amounts
     * @param items Array of identifiers for the purchased items
     * @return bool True if all discounted purchases were successful
     */
    function executeBulkPurchase(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256[] memory amounts,
        bytes32[] memory items
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amounts.length == items.length, "Arrays length mismatch");
        require(amounts.length > 0, "Empty purchase list");

        uint256 totalDiscountedAmount = 0;
        uint256 purchasedCounts = getPurchaseCount(sendAccountId);

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            require(items[i] != bytes32(0), "Invalid item identifier");

            uint256 discountedAmount = discount(amounts[i], purchasedCounts);
            totalDiscountedAmount = totalDiscountedAmount.add(discountedAmount);

            emit Discount(sendAccountId, items[i], amounts[i], discountedAmount);
        }

        bool transferResult = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            totalDiscountedAmount,
            keccak256(abi.encodePacked(items)),
            bytes32(purchasedCounts),
            "Bulk discounted purchase",
            keccak256(abi.encodePacked(sendAccountId, fromAccountId, toAccountId, totalDiscountedAmount, block.timestamp))
        );

        if (transferResult) {
            incrementPurchaseCount(sendAccountId);
        }

        return transferResult;
    }

    /**
     * @dev Retrieves discount statistics for an account
     * @param accountId The account to retrieve statistics for
     * @return totalPurchases The total number of purchases made
     * @return totalDiscountedAmount The total amount saved through discounts
     * @return averageDiscountRate The average discount rate applied
     */
    function getDiscountStatistics(bytes32 accountId) external view returns (
        uint256 totalPurchases,
        uint256 totalDiscountedAmount,
        uint256 averageDiscountRate
    ) {
        totalPurchases = getPurchaseCount(accountId);
        totalDiscountedAmount = discountStatistics[accountId].totalDiscountedAmount;
        averageDiscountRate = totalPurchases > 0 ? discountStatistics[accountId].totalDiscountRate.div(totalPurchases) : 0;
    }

    /**
     * @dev Updates discount statistics after a purchase
     * @param accountId The account that made the purchase
     * @param originalAmount The original amount before discount
     * @param discountedAmount The final amount after discount
     */
    function updateDiscountStatistics(bytes32 accountId, uint256 originalAmount, uint256 discountedAmount) internal {
        uint256 discountRate = originalAmount.sub(discountedAmount).mul(100).div(originalAmount);
        discountStatistics[accountId].totalDiscountedAmount = discountStatistics[accountId].totalDiscountedAmount.add(originalAmount.sub(discountedAmount));
        discountStatistics[accountId].totalDiscountRate = discountStatistics[accountId].totalDiscountRate.add(discountRate);
    }

    /**
     * @dev Allows admin to set a temporary promotion discount
     * @param startTime The start time of the promotion
     * @param endTime The end time of the promotion
     * @param discountRate The promotional discount rate (0-100)
     */
    function setPromotionalDiscount(uint256 startTime, uint256 endTime, uint256 discountRate) external onlyAdmin {
        require(startTime < endTime, "Invalid time range");
        require(discountRate <= 100, "Invalid discount rate");
        promotionalDiscount = PromotionalDiscount(startTime, endTime, discountRate);
        emit PromotionalDiscountSet(startTime, endTime, discountRate);
    }

    /**
     * @dev Checks if a promotional discount is active and applies it if so
     * @param amount The original amount
     * @return uint256 The discounted amount after applying promotional discount if active
     */
    function applyPromotionalDiscount(uint256 amount) public view returns (uint256) {
        if (block.timestamp >= promotionalDiscount.startTime && block.timestamp <= promotionalDiscount.endTime) {
            uint256 discountAmount = amount.mul(promotionalDiscount.discountRate).div(100);
            return amount.sub(discountAmount);
        }
        return amount;
    }

    /**
     * @dev Executes a purchase with consideration for promotional discounts
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the purchased item
     * @return bool True if the discounted purchase was successful
     */
    function executePurchaseWithPromotion(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(item != bytes32(0), "Invalid item identifier");

        uint256 purchasedCounts = getPurchaseCount(sendAccountId);
        uint256 discountedAmount = discount(amount, purchasedCounts);
        discountedAmount = applyPromotionalDiscount(discountedAmount);

        bool result = customTransfer(
            sendAccountId,
            fromAccountId,
            toAccountId,
            discountedAmount,
            item,
            bytes32(purchasedCounts),
            string(abi.encodePacked("Promotional discounted purchase of ", item)),
            keccak256(abi.encodePacked(sendAccountId, fromAccountId, toAccountId, discountedAmount, item, block.timestamp))
        );

        if (result) {
            emit Discount(sendAccountId, item, amount, discountedAmount);
            incrementPurchaseCount(sendAccountId);
            updateDiscountStatistics(sendAccountId, amount, discountedAmount);
        }

        return result;
    }

    /**
     * @dev Retrieves the current promotional discount information
     * @return startTime The start time of the current promotion
     * @return endTime The end time of the current promotion
     * @return discountRate The current promotional discount rate
     */
    function getPromotionalDiscount() external view returns (uint256 startTime, uint256 endTime, uint256 discountRate) {
        return (promotionalDiscount.startTime, promotionalDiscount.endTime, promotionalDiscount.discountRate);
    }

    /**
     * @dev Allows admin to set a referral bonus rate
     * @param rate The referral bonus rate (0-100)
     */
    function setReferralBonusRate(uint256 rate) external onlyAdmin {
        require(rate <= 100, "Invalid referral bonus rate");
        referralBonusRate = rate;
        emit ReferralBonusRateSet(rate);
    }

    /**
     * @dev Executes a purchase with a referral bonus
     * @param sendAccountId Account initiating the purchase
     * @param fromAccountId Source account for funds
     * @param toAccountId Destination account (usually merchant)
     * @param amount Original purchase amount
     * @param item Identifier of the purchased item
     * @param referrerAccountId Account that referred the purchaser
     * @return bool True if the discounted purchase and referral bonus were successful
     */
    function executePurchaseWithReferral(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 item,
        bytes32 referrerAccountId
    ) external returns (bool) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(item != bytes32(0), "Invalid item identifier");
        require(referrerAccountId != bytes32(0), "Invalid referrerAccountId");

        uint256 purch