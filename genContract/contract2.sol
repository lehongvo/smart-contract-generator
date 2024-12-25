// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract DiscountContract is IDiscount, Ownable, Pausable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;

    // State variables
    IOracle public oracle;
    ITransferable public token;
    uint256 public oracleId;
    
    // Mapping to store account balances
    mapping(bytes32 => uint256) private accountBalances;
    
    // Mapping to store account statuses (active/inactive)
    mapping(bytes32 => bool) private accountActive;
    
    // Mapping to store purchase counts for each account
    mapping(bytes32 => uint256) private purchaseCounts;

    // Constants for discount tiers
    uint256 private constant TIER1_THRESHOLD = 5;
    uint256 private constant TIER2_THRESHOLD = 10;
    uint256 private constant TIER3_THRESHOLD = 20;
    
    uint256 private constant TIER1_DISCOUNT = 5; // 5% discount
    uint256 private constant TIER2_DISCOUNT = 10; // 10% discount
    uint256 private constant TIER3_DISCOUNT = 15; // 15% discount
    uint256 private constant MAX_DISCOUNT = 20; // 20% max discount

    // Events
    event AccountCreated(bytes32 indexed accountId);
    event AccountDeactivated(bytes32 indexed accountId);
    event BalanceUpdated(bytes32 indexed accountId, uint256 newBalance);
    event OracleUpdated(uint256 indexed newOracleId);

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
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Check if accounts exist and are active
        require(_accountExists(sendAccountId), "Send account does not exist");
        require(_accountExists(fromAccountId), "From account does not exist");
        require(_accountExists(toAccountId), "To account does not exist");
        require(_isAccountActive(sendAccountId), "Send account is not active");
        require(_isAccountActive(fromAccountId), "From account is not active");
        require(_isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(_getBalance(fromAccountId) >= amount, "Insufficient balance in source account");

        // Get purchase history count for discount calculation
        uint256 purchaseCount = _getPurchaseCount(sendAccountId);

        // Calculate discounted amount
        uint256 discountedAmount = discount(amount, purchaseCount);

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

        // Update purchase count
        _incrementPurchaseCount(sendAccountId);

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Checks if an account exists
     * @param accountId Account identifier to check
     * @return bool True if account exists, false otherwise
     */
    function _accountExists(bytes32 accountId) internal view returns (bool) {
        // Implementation depends on how accounts are stored
        // For this example, we'll assume a mapping of accountId to bool
        return accounts[accountId];
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account identifier to check
     * @return bool True if account is active, false otherwise
     */
    function _isAccountActive(bytes32 accountId) internal view returns (bool) {
        // Implementation depends on how account status is stored
        // For this example, we'll assume a mapping of accountId to bool
        return accountStatus[accountId];
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account identifier to check
     * @return uint256 Balance of the account
     */
    function _getBalance(bytes32 accountId) internal view returns (uint256) {
        // Implementation depends on how balances are stored
        // For this example, we'll assume a mapping of accountId to uint256
        return balances[accountId];
    }

    /**
     * @dev Gets the purchase count for an account
     * @param accountId Account identifier to check
     * @return uint256 Number of purchases made by the account
     */
    function _getPurchaseCount(bytes32 accountId) internal view returns (uint256) {
        // Implementation depends on how purchase counts are stored
        // For this example, we'll assume a mapping of accountId to uint256
        return purchaseCounts[accountId];
    }

    /**
     * @dev Increments the purchase count for an account
     * @param accountId Account identifier to increment
     */
    function _incrementPurchaseCount(bytes32 accountId) internal {
        // Implementation depends on how purchase counts are stored
        // For this example, we'll assume a mapping of accountId to uint256
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Sets the oracle ID for price feeds
     * @param newOracleId New oracle ID to set
     * @notice Only callable by contract owner
     */
    function setOracleId(uint256 newOracleId) external override onlyOwner {
        require(newOracleId > 0, "Invalid oracle ID");
        require(oracle.get(newOracleId, "ACTIVE") == bytes32(uint256(1)), "Oracle is not active");

        oracleId = newOracleId;
        emit OracleIdUpdated(newOracleId);
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
     * @return string Version of the contract
     */
    function version() external pure override returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Initializes the contract with dependencies
     * @param _oracle Oracle contract address
     * @param _token Token contract address
     * @notice Can only be called once
     */
    function initialize(IOracle _oracle, ITransferable _token) external override initializer {
        require(address(_oracle) != address(0), "Invalid oracle address");
        require(address(_token) != address(0), "Invalid token address");

        __Ownable_init();
        oracle = _oracle;
        token = _token;

        // Set initial oracle ID
        oracleId = 1; // Assuming 1 is a valid initial oracle ID
        require(oracle.get(oracleId, "ACTIVE") == bytes32(uint256(1)), "Initial oracle is not active");

        emit ContractInitialized(address(_oracle), address(_token));
    }

    /**
     * @dev Upgrades the contract to a new implementation
     * @param newImplementation Address of the new implementation contract
     * @notice Only callable by contract owner
     */
    function upgradeTo(address newImplementation) external onlyOwner {
        require(newImplementation != address(0), "Invalid implementation address");
        require(newImplementation != address(this), "Cannot upgrade to same implementation");

        _upgradeToAndCall(newImplementation, "", false);
        emit ContractUpgraded(newImplementation);
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

    /**
     * @dev Withdraws any stuck tokens from the contract
     * @param tokenAddress Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * @notice Only callable by contract owner
     */
    function withdrawStuckTokens(address tokenAddress, uint256 amount) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(tokenAddress);
        require(tokenContract.transfer(owner(), amount), "Token transfer failed");

        emit StuckTokensWithdrawn(tokenAddress, amount);
    }

    /**
     * @dev Updates the token contract address
     * @param newTokenAddress Address of the new token contract
     * @notice Only callable by contract owner
     */
    function updateTokenAddress(address newTokenAddress) external onlyOwner {
        require(newTokenAddress != address(0), "Invalid token address");
        require(newTokenAddress != address(token), "New address is the same as current");

        address oldTokenAddress = address(token);
        token = ITransferable(newTokenAddress);

        emit TokenAddressUpdated(oldTokenAddress, newTokenAddress);
    }

    /**
     * @dev Updates the oracle contract address
     * @param newOracleAddress Address of the new oracle contract
     * @notice Only callable by contract owner
     */
    function updateOracleAddress(address newOracleAddress) external onlyOwner {
        require(newOracleAddress != address(0), "Invalid oracle address");
        require(newOracleAddress != address(oracle), "New address is the same as current");

        address oldOracleAddress = address(oracle);
        oracle = IOracle(newOracleAddress);

        emit OracleAddressUpdated(oldOracleAddress, newOracleAddress);
    }

    /**
     * @dev Sets a custom discount rate for a specific account
     * @param accountId Account identifier
     * @param discountRate Custom discount rate (in basis points, e.g., 500 for 5%)
     * @notice Only callable by contract owner
     */
    function setCustomDiscountRate(bytes32 accountId, uint256 discountRate) external onlyOwner {
        require(accountId != bytes32(0), "Invalid account ID");
        require(discountRate <= 10000, "Discount rate cannot exceed 100%");

        customDiscountRates[accountId] = discountRate;
        emit CustomDiscountRateSet(accountId, discountRate);
    }

    /**
     * @dev Removes a custom discount rate for a specific account
     * @param accountId Account identifier
     * @notice Only callable by contract owner
     */
    function removeCustomDiscountRate(bytes32 accountId) external onlyOwner {
        require(accountId != bytes32(0), "Invalid account ID");
        require(customDiscountRates[accountId] > 0, "No custom discount rate set for this account");

        delete customDiscountRates[accountId];
        emit CustomDiscountRateRemoved(accountId);
    }

    /**
     * @dev Gets the custom discount rate for a specific account
     * @param accountId Account identifier
     * @return uint256 Custom discount rate (in basis points)
     */
    function getCustomDiscountRate(bytes32 accountId) external view returns (uint256) {
        return customDiscountRates[accountId];
    }

    /**
     * @dev Sets a global discount rate
     * @param discountRate Global discount rate (in basis points, e.g., 500 for 5%)
     * @notice Only callable by contract owner
     */
    function setGlobalDiscountRate(uint256 discountRate) external onlyOwner {
        require(discountRate <= 10000, "Discount rate cannot exceed 100%");

        globalDiscountRate = discountRate;
        emit GlobalDiscountRateUpdated(discountRate);
    }

    /**
     * @dev Gets the current global discount rate
     * @return uint256 Global discount rate (in basis points)
     */
    function getGlobalDiscountRate() external view returns (uint256) {
        return globalDiscountRate;
    }

    /**
     * @dev Adds a new discount tier
     * @param minPurchaseCount Minimum purchase count for this tier
     * @param discountRate Discount rate for this tier (in basis points)
     * @notice Only callable by contract owner
     */
    function addDiscountTier(uint256 minPurchaseCount, uint256 discountRate) external onlyOwner {
        require(minPurchaseCount > 0, "Minimum purchase count must be greater than 0");
        require(discountRate <= 10000, "Discount rate cannot exceed 100%");

        discountTiers.push(DiscountTier({
            minPurchaseCount: minPurchaseCount,
            discountRate: discountRate
        }));

        // Sort discount tiers by minPurchaseCount in descending order
        for (uint256 i = discountTiers.length - 1; i > 0; i--) {
            if (discountTiers[i].minPurchaseCount > discountTiers[i - 1].minPurchaseCount) {
                DiscountTier memory temp = discountTiers[i];
                discountTiers[i] = discountTiers[i - 1];
                discountTiers[i - 1] = temp;
            } else {
                break;
            }
        }

        emit DiscountTierAdded(minPurchaseCount, discountRate);
    }

    /**
     * @dev Removes a discount tier
     * @param index Index of the discount tier to remove
     * @notice Only callable by contract owner
     */
    function removeDiscountTier(uint256 index) external onlyOwner {
        require(index < discountTiers.length, "Invalid discount tier index");

        DiscountTier memory removedTier = discountTiers[index];

        for (uint256 i = index; i < discountTiers.length - 1; i++) {
            discountTiers[i] = discountTiers[i + 1];
        }
        discountTiers.pop();

        emit DiscountTierRemoved(removedTier.minPurchaseCount, removedTier.discountRate);
    }

    /**
     * @dev Gets all discount tiers
     * @return DiscountTier[] Array of all discount tiers
     */
    function getDiscountTiers() external view returns (DiscountTier[] memory) {
        return discountTiers;
    }

    /**
     * @dev Calculates the effective discount rate for a given purchase count
     * @param purchaseCount Number of purchases made by the account
     * @return uint256 Effective discount rate (in basis points)
     */
    function calculateEffectiveDiscountRate(uint256 purchaseCount) public view returns (uint256) {
        for (uint256 i = 0; i < discountTiers.length; i++) {
            if (purchaseCount >= discountTiers[i].minPurchaseCount) {
                return disc

Here is PART 3 of the smart contract implementation for the IDiscount interface:

// BEGIN PART 3

    /**
     * @dev Helper function to calculate tiered discount rate
     * @param purchasedCounts Number of previous purchases
     * @return Discount rate as a percentage (0-100)
     */
    function _calculateDiscountRate(uint256 purchasedCounts) internal pure returns (uint256) {
        if (purchasedCounts >= 100) {
            return 20; // 20% discount for 100+ purchases
        } else if (purchasedCounts >= 50) {
            return 15; // 15% discount for 50-99 purchases
        } else if (purchasedCounts >= 25) {
            return 10; // 10% discount for 25-49 purchases
        } else if (purchasedCounts >= 10) {
            return 5; // 5% discount for 10-24 purchases
        } else {
            return 0; // No discount for <10 purchases
        }
    }

    /**
     * @dev Helper function to apply discount to an amount
     * @param amount Original amount
     * @param discountRate Discount rate as a percentage (0-100)
     * @return Discounted amount
     */
    function _applyDiscount(uint256 amount, uint256 discountRate) internal pure returns (uint256) {
        require(discountRate <= 100, "Invalid discount rate");
        uint256 discountAmount = amount.mul(discountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Helper function to validate account existence and activity
     * @param accountId Account to validate
     */
    function _validateAccount(bytes32 accountId) internal view {
        require(accountId != bytes32(0), "Invalid account ID");
        // Additional logic to check if account exists and is active
        // This would typically involve querying a separate account management contract
        // or checking against a mapping of active accounts
        // For this example, we'll assume all non-zero accountIds are valid and active
    }

    /**
     * @dev Helper function to check if an address is the contract owner
     * @param addr Address to check
     * @return True if address is the contract owner
     */
    function _isOwner(address addr) internal view returns (bool) {
        return addr == owner;
    }

    /**
     * @dev Helper function to transfer tokens between accounts
     * @param fromAccountId Source account
     * @param toAccountId Destination account
     * @param amount Amount to transfer
     */
    function _transferTokens(bytes32 fromAccountId, bytes32 toAccountId, uint256 amount) internal {
        require(token.customTransfer(fromAccountId, fromAccountId, toAccountId, amount, bytes32(0), bytes32(0), "Discount transfer", bytes32(0)), "Token transfer failed");
    }

    /**
     * @dev Helper function to get current price from oracle
     * @param item Item identifier
     * @return Current price of the item
     */
    function _getCurrentPrice(bytes32 item) internal view returns (uint256) {
        (bytes32 priceBytes, string memory err) = oracle.get(currentOracleId, item);
        require(bytes(err).length == 0, "Oracle error");
        return uint256(priceBytes);
    }

    /**
     * @dev Helper function to update purchase history
     * @param accountId Account making the purchase
     * @param item Item being purchased
     */
    function _updatePurchaseHistory(bytes32 accountId, bytes32 item) internal {
        purchaseHistory[accountId][item] = purchaseHistory[accountId][item].add(1);
        totalPurchases[accountId] = totalPurchases[accountId].add(1);
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
        
        uint256 discountRate = _calculateDiscountRate(purchasedCounts);
        return _applyDiscount(amount, discountRate);
    }

    /**
     * @dev Executes a purchase with discount applied
     * @param accountId Account making the purchase
     * @param item Item being purchased
     * @return Final discounted amount charged
     */
    function purchaseWithDiscount(bytes32 accountId, bytes32 item) external returns (uint256) {
        _validateAccount(accountId);
        
        uint256 originalPrice = _getCurrentPrice(item);
        uint256 purchasedCounts = totalPurchases[accountId];
        uint256 discountedAmount = discount(originalPrice, purchasedCounts);
        
        _transferTokens(accountId, feeCollector, discountedAmount);
        _updatePurchaseHistory(accountId, item);
        
        emit Discount(accountId, item, originalPrice, discountedAmount);
        
        return discountedAmount;
    }

    /**
     * @dev Gets purchase history for an account and item
     * @param accountId Account to query
     * @param item Item to query
     * @return Number of times the account has purchased the item
     */
    function getPurchaseHistory(bytes32 accountId, bytes32 item) external view returns (uint256) {
        return purchaseHistory[accountId][item];
    }

    /**
     * @dev Gets total purchases for an account
     * @param accountId Account to query
     * @return Total number of purchases made by the account
     */
    function getTotalPurchases(bytes32 accountId) external view returns (uint256) {
        return totalPurchases[accountId];
    }

    /**
     * @dev Sets the fee collector address
     * @param newFeeCollector Address to collect fees
     * @notice Only owner can call this function
     */
    function setFeeCollector(address newFeeCollector) external {
        require(_isOwner(msg.sender), "Only owner can set fee collector");
        require(newFeeCollector != address(0), "Invalid fee collector address");
        feeCollector = newFeeCollector;
    }

    /**
     * @dev Gets the current fee collector address
     * @return Address of the current fee collector
     */
    function getFeeCollector() external view returns (address) {
        return feeCollector;
    }

    /**
     * @dev Withdraws accumulated fees to the owner
     * @notice Only owner can call this function
     */
    function withdrawFees() external {
        require(_isOwner(msg.sender), "Only owner can withdraw fees");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No fees to withdraw");
        require(token.transfer(owner, balance), "Fee transfer failed");
    }

    /**
     * @dev Pauses all discount operations
     * @notice Only owner can call this function
     */
    function pause() external {
        require(_isOwner(msg.sender), "Only owner can pause");
        _pause();
    }

    /**
     * @dev Unpauses all discount operations
     * @notice Only owner can call this function
     */
    function unpause() external {
        require(_isOwner(msg.sender), "Only owner can unpause");
        _unpause();
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
        require(!paused(), "Transfers are paused");
        _validateAccount(sendAccountId);
        _validateAccount(fromAccountId);
        _validateAccount(toAccountId);
        require(amount > 0, "Transfer amount must be greater than 0");
        
        // Perform the transfer using the token contract
        result = token.customTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2, memo, traceId);
        require(result, "Transfer failed");
        
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, amount, miscValue1, miscValue2);
        return true;
    }

    /**
     * @dev Upgrades the contract to a new implementation
     * @param newImplementation Address of the new implementation contract
     * @notice Only owner can call this function
     */
    function upgradeTo(address newImplementation) external {
        require(_isOwner(msg.sender), "Only owner can upgrade");
        _upgradeTo(newImplementation);
    }

    /**
     * @dev Performs any necessary setup after an upgrade
     * @notice This function should be called right after an upgrade
     */
    function postUpgrade() external {
        require(_isOwner(msg.sender), "Only owner can post upgrade");
        // Perform any necessary state migrations or initializations here
    }

    // Fallback function to accept Ether
    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    // Function to withdraw accidentally sent Ether
    function withdrawEther() external {
        require(_isOwner(msg.sender), "Only owner can withdraw Ether");
        uint256 balance = address(this).balance;
        require(balance > 0, "No Ether to withdraw");
        (bool sent, ) = owner.call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    // Event emitted when Ether is received
    event EtherReceived(address sender, uint256 amount);
}