import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

interface ContractInput {
    name?: string;
    type?: "ERC20" | "ERC721";
    features?: {
        security?: {
            reentrancy?: boolean;
            accessControl?: boolean;
            pausable?: boolean;
            blacklist?: boolean;
            whitelist?: boolean;
            rateLimiting?: boolean;
        };
        tokenomics?: {
            dynamicTax?: boolean;
            antiBot?: boolean;
            autoLiquidity?: boolean;
            rewardSystem?: boolean;
            vesting?: boolean;
            maxWalletLimit?: boolean;
            buybackBurn?: boolean;
        };
        advanced?: {
            governance?: boolean;
            staking?: boolean;
            tokenLocking?: boolean;
            multiSig?: boolean;
            crossChain?: boolean;
            batchTransfer?: boolean;
        };
    };
}

class OpenZeppelinStyleGenerator {
    getContractTemplate(input: ContractInput): string {
        return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

${this.getImports(input)}

contract ${input.name || 'Token'} is ${this.getInheritance(input)} {
    using SafeMath for uint256;
    
    // Implementation details...
}`;
    }

    private getImports(input: ContractInput): string {
        const imports = [
            'import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";',
            'import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";',
            'import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";',
            'import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";'
        ];

        if (input.features?.security?.pausable) {
            imports.push('import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";');
        }

        return imports.join('\n');
    }

    private getInheritance(input: ContractInput): string {
        const inheritance = ['ERC20', 'Ownable', 'ReentrancyGuard'];

        if (input.features?.security?.pausable) inheritance.push('Pausable');

        return inheritance.join(', ');
    }
}

const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
});

export async function POST(req: NextRequest) {
    try {
        const { message } = await req.json();

        if (!message) {
            return NextResponse.json(
                { error: 'Message is required' },
                { status: 400 }
            );
        }

        // Check if message is related to Discount contract
        if (message.toLowerCase().includes('discount')) {
            const interfaceTemplate = `// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IOracle {
    function addOracle(uint256 oracleId, address invoker) external;
    function deleteOracle(uint256 oracleId) external;
    function set(
        uint256 oracleId,
        bytes32 key,
        bytes32 value
    ) external;
    
    function setBatch(
        uint256 oracleId,
        bytes32[] memory keys,
        bytes32[] memory values
    ) external;
    
    function get(uint256 oracleId, bytes32 key)
        external
        view
        returns (bytes32 value, string memory err);
    
    function getBatch(uint256 oracleId, bytes32[] memory keys)
        external
        view
        returns (bytes32[] memory values, string memory err);

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
                model: "gpt-4o-mini",
                messages: [
                    {
                        role: "system",
                        content: `You are a smart contract developer. Generate a complete implementation of the given interface. 

REQUIREMENTS:
1. Must implement ALL interface functions with EXACT signatures 
2. All function must have full code implementation and logic
2. If have function in interface, so main contract must have it too and full implementation/logic
2. Must emit ALL events defined in the interface
3. Must match ALL parameter names and return values
4. Create appropriate internal logic for the functions
5. Use SafeMath for calculations where needed
6. Add proper validation checks
7. Include clear documentation

INTERFACE TO IMPLEMENT:
${interfaceTemplate}

Generate only the implementation contract.
Do not include the interface definitions in your response.
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
        } else {
            // Handle other contract types
            let contractInput: ContractInput;
            try {
                contractInput = JSON.parse(message);
            } catch {
                contractInput = {
                    name: "Token",
                    type: "ERC20"
                };
            }

            const generator = new OpenZeppelinStyleGenerator();
            const contractTemplate = generator.getContractTemplate(contractInput);

            const completion = await openai.chat.completions.create({
                model: "gpt-4o-mini",
                messages: [
                    {
                        role: "system",
                        content: `You are a smart contract developer. Generate a complete implementation based on the template and requirements.

Template:
${contractTemplate}

Requirements:
1. Follow OpenZeppelin's best practices
2. Include proper documentation
3. Implement all required features
4. Add appropriate security measures
5. Use clear naming conventions

Generate the complete contract implementation.
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

    } catch (error) {
        console.error('Error:', error);
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}