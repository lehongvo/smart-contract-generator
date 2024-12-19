import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});

export async function POST(req: NextRequest) {
    try {
        const { message } = await req.json();

        if (!message) {
            return NextResponse.json({ error: 'Message is required' }, { status: 400 });
        }

        if (message.toLowerCase().includes('discount')) {
            const baseInterfaces = `// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IOracle {
    function addOracle(uint256 oracleId, address invoker) external;
    function deleteOracle(uint256 oracleId) external;
    function set(uint256 oracleId, bytes32 key, bytes32 value) external;
    function setBatch(uint256 oracleId, bytes32[] memory keys, bytes32[] memory values) external;
    function get(uint256 oracleId, bytes32 key) external view returns (bytes32 value, string memory err);
    function getBatch(uint256 oracleId, bytes32[] memory keys) external view returns (bytes32[] memory values, string memory err);
    
    event AddOracle(uint256 indexed oracleId, address invoker);
    event DeleteOracle(uint256 indexed oracleId);
    event SetOracleValue(uint256 indexed oracleId, bytes32 key, bytes32 value);
}

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

interface IDiscount is ITransferable {
    event Discount(bytes32 sendAccountId, bytes32 item, uint256 amount, uint256 discountedAmount);
    function initialize(IOracle oracle, ITransferable token) external;
    function version() external pure returns (string memory);
    function setOracleId(uint256 oracleId) external;
    function getOracleId() external view returns (uint256);
    function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256);
}`;

            const completion = await openai.chat.completions.create({
                model: "gpt-3.5-turbo",
                messages: [
                    {
                        role: "system",
                        content: `You are a smart contract developer. Generate a DETAILED implementation of the Discount contract based on these exact interfaces. 

THE INTERFACES TO IMPLEMENT:
${baseInterfaces}

REQUIREMENTS:
1. MUST implement ALL functions from IDiscount interface exactly as specified
2. MUST emit ALL events from the interfaces at appropriate times
3. Contract should inherit from Initializable and IDiscount
4. Use SafeMath for all calculations
5. Add detailed error messages and validation
6. Include comprehensive documentation
7. Add helper functions but maintain interface compliance
8. Generate at least 800 lines of detailed code while maintaining quality

IMPLEMENTATION MUST INCLUDE:
1. Proper initialization checks
2. Oracle interaction logic
3. Discount calculation strategies
4. Transfer validation and execution
5. Purchase history tracking
6. Error handling and logging
7. Security measures

Generate ONLY the implementation contract (no interfaces, no libraries).
Do not use markdown formatting.`
                    },
                    {
                        role: "user",
                        content: message
                    }
                ],
                temperature: 0.7,
                max_tokens: 4000
            });

            const contractCode = completion.choices[0].message?.content;

            if (!contractCode) {
                return NextResponse.json(
                    { error: 'Failed to generate contract code' },
                    { status: 500 }
                );
            }

            return NextResponse.json({ contractCode });
        }

        return NextResponse.json(
            { error: 'Unsupported contract type' },
            { status: 400 }
        );

    } catch (error) {
        console.error('Error:', error);
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}