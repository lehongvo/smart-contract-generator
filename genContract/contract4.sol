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
    
    // Constants
    uint256 private constant DISCOUNT_DECIMALS = 2;
    uint256 private constant MAX_DISCOUNT_PERCENTAGE = 5000; // 50% max discount
    
    // Events
    event OracleUpdated(uint256 indexed newOracleId);
    event PurchaseCountIncremented(bytes32 indexed accountId, uint256 newCount);

    // Modifiers
    modifier onlyValidAddress(address _address) {
        require(_address != address(0), "Invalid address: zero address");
        _;
    }

    modifier onlyValidAmount(uint256 _amount) {
        require(_amount > 0, "Invalid amount: must be greater than zero");
        _;
    }

    modifier onlyValidAccountId(bytes32 _accountId) {
        require(_accountId != bytes32(0), "Invalid accountId: must not be empty");
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
        
        // Verify oracle exists and is active
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
     * @notice Amount must be greater than 0
     * @notice Uses tiered discount rates based on purchase history
     */
    function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 discountPercentage;
        
        if (purchasedCounts < 5) {
            discountPercentage = 500; // 5%
        } else if (purchasedCounts < 10) {
            discountPercentage = 1000; // 10%
        } else if (purchasedCounts < 20) {
            discountPercentage = 1500; // 15%
        } else if (purchasedCounts < 50) {
            discountPercentage = 2000; // 20%
        } else {
            discountPercentage = 2500; // 25%
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
    ) external override nonReentrant whenNotPaused returns (bool result) {
        require(sendAccountId != bytes32(0), "Invalid sendAccountId");
        require(fromAccountId != bytes32(0), "Invalid fromAccountId");
        require(toAccountId != bytes32(0), "Invalid toAccountId");
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid traceId");

        // Validate accounts are active
        require(_isAccountActive(sendAccountId), "Send account is not active");
        require(_isAccountActive(fromAccountId), "From account is not active");
        require(_isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(_getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

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
        (bytes32 value, string memory err) = oracle.get(oracleId, accountId);
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Account lookup failed");
        return value == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account to check
     * @return uint256 Account balance
     */
    function _getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracle.get(oracleId, keccak256(abi.encodePacked("BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Balance lookup failed");
        return uint256(value);
    }

    /**
     * @dev Applies discount to the given amount
     * @param accountId Account making the purchase
     * @param amount Original amount
     * @return uint256 Discounted amount
     */
    function _applyDiscount(bytes32 accountId, uint256 amount) internal view returns (uint256) {
        uint256 purchaseCount = purchaseCounts[accountId];
        return discount(amount, purchaseCount);
    }

    /**
     * @dev Increments the purchase count for an account
     * @param accountId Account to increment count for
     */
    function _incrementPurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
        emit PurchaseCountIncremented(accountId, purchaseCounts[accountId]);
    }

    /**
     * @dev Pauses all contract functions
     * @notice Only owner can pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all contract functions
     * @notice Only owner can unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // Additional helper functions and admin operations below

    /**
     * @dev Admin function to manually set purchase count for an account
     * @param accountId Account to set count for
     * @param count New purchase count
     */
    function setAccountPurchaseCount(bytes32 accountId, uint256 count) external onlyOwner {
        require(accountId != bytes32(0), "Invalid accountId");
        purchaseCounts[accountId] = count;
        emit PurchaseCountIncremented(accountId, count);
    }

    /**
     * @dev Retrieves the current purchase count for an account
     * @param accountId Account to check
     * @return uint256 Current purchase count
     */
    function getAccountPurchaseCount(bytes32 accountId) external view returns (uint256) {
        return purchaseCounts[accountId];
    }

    /**
     * @dev Admin function to update the token contract address
     * @param newToken Address of the new token contract
     */
    function updateTokenContract(ITransferable newToken) external onlyOwner onlyValidAddress(address(newToken)) {
        token = newToken;
    }

    /**
     * @dev Admin function to update the oracle contract address
     * @param newOracle Address of the new oracle contract
     */
    function updateOracleContract(IOracle newOracle) external onlyOwner onlyValidAddress(address(newOracle)) {
        oracle = newOracle;
    }

    /**
     * @dev Calculates the effective discount percentage for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return uint256 Discount percentage (2 decimal places, e.g. 1000 = 10.00%)
     */
    function calculateDiscountPercentage(uint256 purchaseCount) public pure returns (uint256) {
        if (purchaseCount < 5) {
            return 500; // 5%
        } else if (purchaseCount < 10) {
            return 1000; // 10%
        } else if (purchaseCount < 20) {
            return 1500; // 15%
        } else if (purchaseCount < 50) {
            return 2000; // 20%
        } else {
            return 2500; // 25%
        }
    }

    /**
     * @dev Simulates a discount calculation without executing a transfer
     * @param accountId Account to calculate discount for
     * @param amount Original purchase amount
     * @return uint256 Simulated discounted amount
     */
    function simulateDiscount(bytes32 accountId, uint256 amount) external view returns (uint256) {
        require(accountId != bytes32(0), "Invalid accountId");
        require(amount > 0, "Amount must be greater than zero");
        
        uint256 purchaseCount = purchaseCounts[accountId];
        return discount(amount, purchaseCount);
    }

    /**
     * @dev Bulk update of purchase counts for multiple accounts
     * @param accountIds Array of account IDs to update
     * @param counts Array of new purchase counts
     * @notice Only owner can perform this operation
     * @notice Arrays must be of equal length
     */
    function bulkUpdatePurchaseCounts(bytes32[] memory accountIds, uint256[] memory counts) external onlyOwner {
        require(accountIds.length == counts.length, "Array lengths must match");
        
        for (uint256 i = 0; i < accountIds.length; i++) {
            require(accountIds[i] != bytes32(0), "Invalid accountId");
            purchaseCounts[accountIds[i]] = counts[i];
            emit PurchaseCountIncremented(accountIds[i], counts[i]);
        }
    }

    /**
     * @dev Retrieves multiple account purchase counts in a single call
     * @param accountIds Array of account IDs to query
     * @return uint256[] Array of purchase counts
     */
    function getMultipleAccountPurchaseCounts(bytes32[] memory accountIds) external view returns (uint256[] memory) {
        uint256[] memory results = new uint256[](accountIds.length);
        
        for (uint256 i = 0; i < accountIds.length; i++) {
            results[i] = purchaseCounts[accountIds[i]];
        }
        
        return results;
    }

    // END PART 1

Here is PART 2 of the smart contract implementation:

// BEGIN PART 2

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
        
        // Check if oracle exists and is active
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
        require(amount > 0, "Amount must be greater than zero");

        uint256 discountPercentage;
        if (purchasedCounts >= 20) {
            discountPercentage = 20; // 20% discount for 20+ purchases
        } else if (purchasedCounts >= 10) {
            discountPercentage = 15; // 15% discount for 10-19 purchases
        } else if (purchasedCounts >= 5) {
            discountPercentage = 10; // 10% discount for 5-9 purchases
        } else {
            discountPercentage = 5; // 5% discount for 0-4 purchases
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
     * @param miscValue1 First auxiliary parameter for transfer logic (used as item identifier)
     * @param miscValue2 Second auxiliary parameter for transfer logic (used as purchase count)
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
        require(amount > 0, "Amount must be greater than zero");
        require(bytes(memo).length > 0, "Memo cannot be empty");
        require(traceId != bytes32(0), "Invalid trace ID");

        // Validate accounts are active
        require(isAccountActive(sendAccountId), "Send account is not active");
        require(isAccountActive(fromAccountId), "From account is not active");
        require(isAccountActive(toAccountId), "To account is not active");

        // Check balance
        require(getAccountBalance(fromAccountId) >= amount, "Insufficient balance");

        // Apply discount
        uint256 purchaseCount = uint256(miscValue2);
        uint256 discountedAmount = discount(amount, purchaseCount);

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

        // Emit events
        emit CustomTransfer(sendAccountId, fromAccountId, toAccountId, discountedAmount, miscValue1, miscValue2);
        emit Discount(sendAccountId, miscValue1, amount, discountedAmount);

        return true;
    }

    /**
     * @dev Checks if an account is active
     * @param accountId Account identifier to check
     * @return bool True if account is active, false otherwise
     */
    function isAccountActive(bytes32 accountId) internal view returns (bool) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, accountId);
        if (keccak256(abi.encodePacked(err)) != keccak256(abi.encodePacked(""))) {
            return false;
        }
        return value == bytes32(uint256(1));
    }

    /**
     * @dev Gets the balance of an account
     * @param accountId Account identifier to check
     * @return uint256 Account balance
     */
    function getAccountBalance(bytes32 accountId) internal view returns (uint256) {
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("BALANCE", accountId)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Failed to get account balance");
        return uint256(value);
    }

    /**
     * @dev Applies a bulk discount to multiple purchases
     * @param amounts Array of original purchase amounts
     * @param purchaseCounts Array of previous purchase counts for each transaction
     * @return discountedAmounts Array of discounted amounts
     * @notice Arrays must be of equal length
     * @notice All amounts must be greater than zero
     */
    function bulkDiscount(uint256[] memory amounts, uint256[] memory purchaseCounts) 
        external
        pure
        returns (uint256[] memory discountedAmounts)
    {
        require(amounts.length == purchaseCounts.length, "Array lengths must match");
        require(amounts.length > 0, "Arrays cannot be empty");

        discountedAmounts = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than zero");
            discountedAmounts[i] = discount(amounts[i], purchaseCounts[i]);
        }

        return discountedAmounts;
    }

    /**
     * @dev Retrieves the current discount rate for a given purchase count
     * @param purchaseCount Number of previous purchases
     * @return discountRate Current discount rate as a percentage
     */
    function getDiscountRate(uint256 purchaseCount) external pure returns (uint256 discountRate) {
        if (purchaseCount >= 20) {
            return 20;
        } else if (purchaseCount >= 10) {
            return 15;
        } else if (purchaseCount >= 5) {
            return 10;
        } else {
            return 5;
        }
    }

    /**
     * @dev Calculates the savings from a discount
     * @param originalAmount Original purchase amount
     * @param discountedAmount Final amount after discount
     * @return savings Amount saved due to discount
     */
    function calculateSavings(uint256 originalAmount, uint256 discountedAmount) 
        external 
        pure 
        returns (uint256 savings) 
    {
        require(originalAmount >= discountedAmount, "Invalid amounts");
        return originalAmount.sub(discountedAmount);
    }

    /**
     * @dev Applies a time-limited discount to a purchase
     * @param amount Original purchase amount
     * @param purchaseCount Number of previous purchases
     * @param timestamp Current timestamp
     * @param startTime Start time of the discount period
     * @param endTime End time of the discount period
     * @return discountedAmount Final amount after time-limited discount
     */
    function timeLimitedDiscount(
        uint256 amount,
        uint256 purchaseCount,
        uint256 timestamp,
        uint256 startTime,
        uint256 endTime
    ) 
        external 
        pure 
        returns (uint256 discountedAmount) 
    {
        require(amount > 0, "Amount must be greater than zero");
        require(startTime < endTime, "Invalid time range");

        if (timestamp >= startTime && timestamp <= endTime) {
            // Apply an additional 5% discount during the specified time period
            uint256 regularDiscount = discount(amount, purchaseCount);
            uint256 additionalDiscount = regularDiscount.mul(5).div(100);
            return regularDiscount.sub(additionalDiscount);
        } else {
            return discount(amount, purchaseCount);
        }
    }

    /**
     * @dev Applies a discount based on the total purchase value
     * @param amounts Array of purchase amounts
     * @return discountedAmounts Array of discounted amounts
     * @notice Applies a higher discount rate for larger total purchases
     */
    function valueBasedDiscount(uint256[] memory amounts) 
        external 
        pure 
        returns (uint256[] memory discountedAmounts) 
    {
        require(amounts.length > 0, "Array cannot be empty");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than zero");
            totalAmount = totalAmount.add(amounts[i]);
        }

        uint256 discountRate;
        if (totalAmount >= 10000 ether) {
            discountRate = 25; // 25% discount for purchases over 10,000 ether
        } else if (totalAmount >= 5000 ether) {
            discountRate = 20; // 20% discount for purchases between 5,000 and 9,999 ether
        } else if (totalAmount >= 1000 ether) {
            discountRate = 15; // 15% discount for purchases between 1,000 and 4,999 ether
        } else {
            discountRate = 10; // 10% discount for purchases under 1,000 ether
        }

        discountedAmounts = new uint256[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            discountedAmounts[i] = amounts[i].sub(amounts[i].mul(discountRate).div(100));
        }

        return discountedAmounts;
    }

    /**
     * @dev Applies a referral discount to a purchase
     * @param amount Original purchase amount
     * @param purchaseCount Number of previous purchases
     * @param referralCode Referral code used for the purchase
     * @return discountedAmount Final amount after referral discount
     * @notice Applies an additional discount if a valid referral code is used
     */
    function referralDiscount(
        uint256 amount,
        uint256 purchaseCount,
        bytes32 referralCode
    ) 
        external 
        view 
        returns (uint256 discountedAmount) 
    {
        require(amount > 0, "Amount must be greater than zero");
        require(referralCode != bytes32(0), "Invalid referral code");

        uint256 baseDiscountedAmount = discount(amount, purchaseCount);

        // Check if referral code is valid
        (bytes32 value, string memory err) = oracleContract.get(currentOracleId, keccak256(abi.encodePacked("REFERRAL", referralCode)));
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Failed to validate referral code");

        if (value == bytes32(uint256(1))) {
            // Apply an additional 5% discount for valid referral codes
            uint256 referralDiscount = baseDiscountedAmount.mul(5).div(100);
            return baseDiscountedAmount.sub(referralDiscount);
        } else {
            return baseDiscountedAmount;
        }
    }

    /**
     * @dev Calculates a dynamic discount rate based on market conditions
     * @return dynamicRate Current dynamic discount rate
     * @notice Fetches market data from oracle to determine the discount rate
     */
    function getDynamicDiscountRate() external view returns (uint256 dynamicRate) {
        (bytes32 marketIndexValue, string memory err) = oracleContract.get(currentOracleId, "MARKET_INDEX");
        require(keccak256(abi.encodePacked(err)) == keccak256(abi.encodePacked("")), "Failed to get market index");

        uint256 marketIndex = uint256(marketIndexValue);

        if (marketIndex >= 1000) {
            return 5; // 5% discount for high market index
        } else if (marketIndex >= 500) {
            return 10; // 10% discount for medium market index
        } else {
            return 15; // 15% discount for low market index
        }
    }

    /**
     * @dev Applies a combo discount for purchasing multiple items
     * @param amounts Array of original purchase amounts for each item
     * @param itemTypes Array of item type identifiers
     * @return discountedAmounts Array of discounted amounts
     * @notice Applies an additional discount when certain item combinations are purchased
     */
    function comboDiscount(uint256[] memory amounts, bytes32[] memory itemTypes) 
        external 
        pure 
        returns (uint256[] memory discountedAmounts) 
    {
        require(amounts.length == itemTypes.length, "Array lengths must match");
        require(amounts.length > 0, "Arrays cannot be empty");

        discountedAmounts = new uint256[](amounts.length);
        bool hasCombo = false;

        // Check for specific item combinations
        if (amounts.length >= 2) {
            for (uint256 i = 0; i < amounts.length - 1; i++) {
                for (uint256 j = i + 1; j < amounts.length; j++) {
                    if ((itemTypes[i] == bytes32("TYPE_A") && itemTypes[j] == bytes32("TYPE_B")) ||
                        (itemTypes[i] == bytes32("TYPE_B") && itemTypes[j] == bytes32("TYPE_A"))) {
                        hasCombo = true;
                        break;
                    }

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
            discountPercentage = 5; // 5% discount for 1-4 purchases
        } else if (purchasedCounts < 10) {
            discountPercentage = 10; // 10% discount for 5-9 purchases
        } else if (purchasedCounts < 20) {
            discountPercentage = 15; // 15% discount for 10-19 purchases
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
     * @param item Identifier of the purchased item
     * @param purchasedCounts Number of previous purchases by account
     * @param memo Human readable transfer description
     * @param traceId Unique identifier for tracking this transaction
     * @return result True if transfer completed successfully
     */
    function applyDiscountAndTransfer(
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
     * @dev Internal function to validate account IDs
     * @param accountId Account ID to validate
     */
    function validateAccountId(bytes32 accountId) internal pure {
        require(accountId != bytes32(0), "Invalid account ID");
    }

    /**
     * @dev Internal function to check if the caller is the admin
     */
    function _onlyAdmin() internal view {
        require(msg.sender == admin, "Caller is not the admin");
    }

    /**
     * @dev Internal function to check if the oracle is initialized
     */
    function _checkOracleInitialized() internal view {
        require(address(oracle) != address(0), "Oracle not initialized");
    }

    /**
     * @dev Internal function to check if the token is initialized
     */
    function _checkTokenInitialized() internal view {
        require(address(token) != address(0), "Token not initialized");
    }

    /**
     * @dev Internal function to get a value from the oracle
     * @param key The key to look up in the oracle
     * @return value The value retrieved from the oracle
     */
    function _getOracleValue(bytes32 key) internal view returns (bytes32 value) {
        _checkOracleInitialized();
        (value, ) = oracle.get(oracleId, key);
        require(value != bytes32(0), "Oracle value not found");
        return value;
    }

    /**
     * @dev Internal function to convert bytes32 to uint256
     * @param _bytes32 The bytes32 value to convert
     * @return result The uint256 result
     */
    function _bytes32ToUint(bytes32 _bytes32) internal pure returns (uint256 result) {
        return uint256(_bytes32);
    }

    /**
     * @dev Internal function to convert uint256 to bytes32
     * @param _uint The uint256 value to convert
     * @return result The bytes32 result
     */
    function _uintToBytes32(uint256 _uint) internal pure returns (bytes32 result) {
        return bytes32(_uint);
    }

    /**
     * @dev Internal function to calculate the tier based on purchase count
     * @param purchasedCounts Number of previous purchases
     * @return tier The calculated tier
     */
    function _calculateTier(uint256 purchasedCounts) internal pure returns (uint256 tier) {
        if (purchasedCounts < 5) {
            return 1;
        } else if (purchasedCounts < 10) {
            return 2;
        } else if (purchasedCounts < 20) {
            return 3;
        } else {
            return 4;
        }
    }

    /**
     * @dev Internal function to get the discount rate for a specific tier
     * @param tier The tier to get the discount rate for
     * @return discountRate The discount rate for the given tier
     */
    function _getDiscountRateForTier(uint256 tier) internal view returns (uint256 discountRate) {
        bytes32 key = keccak256(abi.encodePacked("DISCOUNT_RATE_TIER_", tier));
        return _bytes32ToUint(_getOracleValue(key));
    }

    /**
     * @dev Internal function to update purchase count for an account
     * @param accountId The account to update the purchase count for
     */
    function _updatePurchaseCount(bytes32 accountId) internal {
        purchaseCounts[accountId] = purchaseCounts[accountId].add(1);
    }

    /**
     * @dev Internal function to check if an account is eligible for a special promotion
     * @param accountId The account to check for promotion eligibility
     * @return isEligible True if the account is eligible for a promotion
     */
    function _isEligibleForPromotion(bytes32 accountId) internal view returns (bool isEligible) {
        uint256 lastPurchaseTimestamp = lastPurchaseTimestamps[accountId];
        if (lastPurchaseTimestamp == 0) {
            return false;
        }
        uint256 daysSinceLastPurchase = (block.timestamp - lastPurchaseTimestamp) / 1 days;
        return daysSinceLastPurchase > 30; // Eligible if no purchase in the last 30 days
    }

    /**
     * @dev Internal function to apply a special promotion discount
     * @param amount The original amount before discount
     * @return discountedAmount The amount after applying the promotion discount
     */
    function _applyPromotionDiscount(uint256 amount) internal view returns (uint256 discountedAmount) {
        bytes32 promotionRateKey = keccak256(abi.encodePacked("PROMOTION_DISCOUNT_RATE"));
        uint256 promotionRate = _bytes32ToUint(_getOracleValue(promotionRateKey));
        uint256 discountAmount = amount.mul(promotionRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to log a purchase for analytics
     * @param accountId The account that made the purchase
     * @param item The item that was purchased
     * @param amount The amount of the purchase
     * @param discountedAmount The discounted amount of the purchase
     */
    function _logPurchase(bytes32 accountId, bytes32 item, uint256 amount, uint256 discountedAmount) internal {
        lastPurchaseTimestamps[accountId] = block.timestamp;
        totalPurchaseAmount[accountId] = totalPurchaseAmount[accountId].add(discountedAmount);
        purchaseHistory[accountId].push(PurchaseRecord({
            timestamp: block.timestamp,
            item: item,
            amount: amount,
            discountedAmount: discountedAmount
        }));
    }

    /**
     * @dev Internal function to check if an account is a VIP
     * @param accountId The account to check for VIP status
     * @return isVip True if the account is a VIP
     */
    function _isVip(bytes32 accountId) internal view returns (bool isVip) {
        uint256 vipThreshold = _bytes32ToUint(_getOracleValue(keccak256(abi.encodePacked("VIP_THRESHOLD"))));
        return totalPurchaseAmount[accountId] >= vipThreshold;
    }

    /**
     * @dev Internal function to apply VIP discount
     * @param amount The original amount before discount
     * @return discountedAmount The amount after applying the VIP discount
     */
    function _applyVipDiscount(uint256 amount) internal view returns (uint256 discountedAmount) {
        bytes32 vipDiscountRateKey = keccak256(abi.encodePacked("VIP_DISCOUNT_RATE"));
        uint256 vipDiscountRate = _bytes32ToUint(_getOracleValue(vipDiscountRateKey));
        uint256 discountAmount = amount.mul(vipDiscountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if a specific item is on sale
     * @param item The item to check for sale status
     * @return isOnSale True if the item is on sale
     */
    function _isItemOnSale(bytes32 item) internal view returns (bool isOnSale) {
        bytes32 saleStatusKey = keccak256(abi.encodePacked("ITEM_ON_SALE_", item));
        return _getOracleValue(saleStatusKey) != bytes32(0);
    }

    /**
     * @dev Internal function to apply sale discount for an item
     * @param item The item being purchased
     * @param amount The original amount before discount
     * @return discountedAmount The amount after applying the sale discount
     */
    function _applySaleDiscount(bytes32 item, uint256 amount) internal view returns (uint256 discountedAmount) {
        bytes32 saleDiscountRateKey = keccak256(abi.encodePacked("SALE_DISCOUNT_RATE_", item));
        uint256 saleDiscountRate = _bytes32ToUint(_getOracleValue(saleDiscountRateKey));
        uint256 discountAmount = amount.mul(saleDiscountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if an account has a birthday discount
     * @param accountId The account to check for birthday discount
     * @return hasBirthdayDiscount True if the account has a birthday discount
     */
    function _hasBirthdayDiscount(bytes32 accountId) internal view returns (bool hasBirthdayDiscount) {
        bytes32 birthdayKey = keccak256(abi.encodePacked("BIRTHDAY_", accountId));
        bytes32 birthdayValue = _getOracleValue(birthdayKey);
        if (birthdayValue == bytes32(0)) {
            return false;
        }
        uint256 birthday = _bytes32ToUint(birthdayValue);
        uint256 currentDay = block.timestamp / 1 days;
        return currentDay % 365 == birthday % 365;
    }

    /**
     * @dev Internal function to apply birthday discount
     * @param amount The original amount before discount
     * @return discountedAmount The amount after applying the birthday discount
     */
    function _applyBirthdayDiscount(uint256 amount) internal view returns (uint256 discountedAmount) {
        bytes32 birthdayDiscountRateKey = keccak256(abi.encodePacked("BIRTHDAY_DISCOUNT_RATE"));
        uint256 birthdayDiscountRate = _bytes32ToUint(_getOracleValue(birthdayDiscountRateKey));
        uint256 discountAmount = amount.mul(birthdayDiscountRate).div(100);
        return amount.sub(discountAmount);
    }

    /**
     * @dev Internal function to check if an account has a referral bonus
     * @param accountId The account to check for referral bonus
     * @return hasReferralBonus True if the account has a referral bonus
     */
    function _hasReferralBonus(bytes32 accountId) internal view returns (bool hasReferralBonus) {
        return referralBonuses[accountId] > 0;
    }

    /**
     * @dev Internal function to apply referral bonus
     * @param accountId The account to apply the referral bonus for
     * @param amount The original amount before discount
     * @return discountedAmount The amount after applying the referral bonus
     */
    function _applyReferralBonus(bytes32 accountId, uint256 amount) internal returns (uint256 discountedAmount) {
        uint256 bonusAmount = referralBonuses[accountId];
        if (bonusAmount >= amount) {
            referralBonuses[accountId] = bonusAmount.sub(amount);
            return 0;
        } else {
            referralBonuses[accountId] = 0;
            return amount.sub(bonusAmount);
        }
    }

    /**
     * @dev Internal function to add a referral bonus to an account
     * @param accountId The account to add the referral bonus to
     * @param amount The amount of the referral bonus
     */
    function _addReferralBonus(bytes32 accountId, uint256 amount) internal {
        referralBonuses[accountId] = referralBonuses[accountId].add(amount);
    }

    /**
     * @dev Internal function to check if an item is eligible for bundle discount
     * @param item The item to check for bundle eligibility
     * @return isEligible True if the item is eligible for bundle discount
     */
    function _isEligibleForBundleDiscount(bytes32 item) internal view returns (bool isEligible) {
        bytes32 bundleEligibilityKey = keccak256(abi.encodePacked("BUNDLE_ELIGIBLE_", item));
        return _getOracleValue(bundleEligibilityKey) != bytes32(0);
    }

    /**
     * @dev Internal function to apply bundle discount
     * @param items Array of items in the bundle
     * @param amounts Array of amounts for each item in the bundle
     * @return discountedAmounts Array of discounted amounts for each item
     */
    function _applyBundleDiscount(bytes32[] memory items, uint256[] memory amounts) internal view returns (uint256[] memory discountedAmounts) {
        require(items.length == amounts.length, "Items and amounts length mismatch");
        discountedAmounts = new uint256[](items.length);
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount = totalAmount.add(amounts[i]);
        }

        bytes32 bundleDiscountRateKey = keccak256(abi.encodePacked("BUNDLE_DISCOUNT_RATE"));
        uint256 bundleDiscountRate = _bytes32ToUint(_getOracleValue(bundleDiscountRateKey));
        uint256 discountAmount = totalAmount.mul(bundleDiscountRate).div(100);
        uint256 discountedTotal = totalAmount.sub(discountAmount);

        for (uint256 i = 0; i < amounts.length; i++) {
            discountedAmounts[i] = discountedTotal.mul(amounts[i]).div(