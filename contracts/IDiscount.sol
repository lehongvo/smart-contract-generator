// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
pragma abicoder v2;

/**
 * @dev Custom contract interface used for token transfers
 */
interface ITransferable {
    function customTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2,
        string memory memo,
        bytes32 traceId
    ) external returns (bool result);

    event CustomTransfer(
        bytes32 sendAccountId,
        bytes32 fromAccountId,
        bytes32 toAccountId,
        uint256 amount,
        bytes32 miscValue1,
        bytes32 miscValue2
    );
}

/**
 * @dev Oracle interface for managing external data
 */
interface IOracle {
    function addOracle(uint256 oracleId, address invoker) external;

    function deleteOracle(uint256 oracleId) external;

    function set(uint256 oracleId, bytes32 key, bytes32 value) external;

    function setBatch(
        uint256 oracleId,
        bytes32[] memory keys,
        bytes32[] memory values
    ) external;

    function get(
        uint256 oracleId,
        bytes32 key
    ) external view returns (bytes32 value, string memory err);

    function getBatch(
        uint256 oracleId,
        bytes32[] memory keys
    ) external view returns (bytes32[] memory values, string memory err);

    event AddOracle(uint256 indexed oracleId, address invoker);
    event DeleteOracle(uint256 indexed oracleId);
    event SetOracleValue(uint256 indexed oracleId, bytes32 key, bytes32 value);
}

/**
 * @dev Discount contract interface - Custom contract registered with TransferProxy
 *      Calculates discounts based on purchase history for buyer-product pairs
 */
interface IDiscount is ITransferable {
    /**
     * @dev Event emitted when a discount is applied
     * @param sendAccountId The sender's account ID
     * @param item The item/product code
     * @param amount Original amount before discount
     * @param discountedAmount Final amount after discount
     */
    event Discount(
        bytes32 sendAccountId,
        bytes32 item,
        uint256 amount,
        uint256 discountedAmount
    );

    /**
     * @dev Initialize the contract - can only be called once
     * @param oracle Oracle contract address
     * @param token ITransferable token contract address
     */
    function initialize(IOracle oracle, ITransferable token) external;

    /**
     * @dev Get contract version
     * @return Contract version string
     */
    function version() external pure returns (string memory);

    /**
     * @dev Set Oracle ID
     * @param oracleId Oracle ID registered in Oracle.sol
     */
    function setOracleId(uint256 oracleId) external;

    /**
     * @dev Get Oracle ID
     * @return Current Oracle ID
     */
    function getOracleId() external view returns (uint256);

    /**
     * @dev Public version of discount calculation (for unit testing)
     * @param amount Purchase amount
     * @param purchasedCounts Number of previous purchases
     * @return Discounted amount (may be same as input if no discount applies)
     */
    function discount(
        uint256 amount,
        uint256 purchasedCounts
    ) external pure returns (uint256) {
        // 
    };

    /**
     * @dev Custom transfer function (inherited from ITransferable)
     * Only executes when miscValue1 is bytes32("discount")
     * @param sendAccountId Sender account ID
     * @param fromAccountId Source account ID
     * @param toAccountId Destination account ID
     * @param amount Transfer amount
     * @param miscValue1 Must be bytes32("discount") to trigger discount logic
     * @param miscValue2 Product code
     * @param memo Transfer memo
     * @param traceId Trace ID for tracking
     * @return Whether to continue to next custom contract
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
    ) external override returns (bool);
}
