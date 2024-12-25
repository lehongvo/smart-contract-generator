import { NextRequest, NextResponse } from "next/server";
import { BedrockRuntimeClient, InvokeModelCommand } from "@aws-sdk/client-bedrock-runtime";

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

// Initialize AWS Bedrock client
const client = new BedrockRuntimeClient({
    region: "ap-northeast-1",
    credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
        sessionToken: process.env.AWS_SESSION_TOKEN
    }
});

async function generateWithBedrock(message: string, systemPrompt: string, part: number = 1, totalParts: number = 3) {
    const input = {
        modelId: "anthropic.claude-3-5-sonnet-20240620-v1:0",
        contentType: "application/json",
        accept: "application/json",
        body: JSON.stringify({
            anthropic_version: "bedrock-2023-05-31",
            messages: [
                {
                    role: "user",
                    content: [
                        {
                            type: "text",
                            text: `Generate PART ${part} of ${totalParts} of the smart contract:

${part === 1 ? `PART 1: Contract declaration, state variables, events, constructor, and modifiers
IMPORTANT: End with a comment saying "// END PART 1"` : ''}

${part === 2 ? `PART 2: Core interface functions and main business logic
IMPORTANT: Start with "// BEGIN PART 2" and end with "// END PART 2"` : ''}

${part === 3 ? `PART 3: Helper functions and remaining implementation
IMPORTANT: Start with "// BEGIN PART 3"` : ''}

${systemPrompt}\n\n${message}`
                        }
                    ]
                }
            ],
            max_tokens: 10000,
            temperature: 0.7
        })
    };

    try {
        const command = new InvokeModelCommand(input);
        const response = await client.send(command);
        const responseBody = JSON.parse(new TextDecoder().decode(response.body));

        if (responseBody.content && Array.isArray(responseBody.content)) {
            return responseBody.content.map(item => item.text).join("\n");
        }
        return responseBody;
    } catch (error) {
        console.error("Error calling Bedrock:", error);
        throw error;
    }
}

// Usage example:
async function generateFullContract(message: string, systemPrompt: string) {
    const part1 = await generateWithBedrock(message, systemPrompt, 1);
    const part2 = await generateWithBedrock(message, systemPrompt, 2);
    const part3 = await generateWithBedrock(message, systemPrompt, 3);

    return [part1, part2, part3].join('\n\n');
}

export async function POST(req: NextRequest) {
    try {
        const { message } = await req.json();

        if (!message) {
            return NextResponse.json(
                { error: 'Message is required' },
                { status: 400 }
            );
        }

        if (message.toLowerCase().includes('discount')) {
            const interfaceTemplate = `// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title Oracle Interface
 * @dev Interface for managing price feeds and oracle data points
 */
interface IOracle {
    /**
 * @dev Adds a new oracle data provider to the system
 * @param oracleId Unique identifier for the oracle (must be > 0), used to track this provider
 * @param invoker Address that will be authorized to update oracle values and must be valid
 * @notice Requires admin privileges to execute
 * @notice OracleId must not already exist in the system
 * @notice Invoker address cannot be zero address
 */
function addOracle(uint256 oracleId, address invoker) external;

/**
 * @dev Removes an existing oracle from the system
 * @param oracleId Identifier of oracle to be deleted
 * @notice Only callable by system admin
 * @notice Oracle must exist and be active
 * @notice Cleans up all associated data for this oracle
 */
function deleteOracle(uint256 oracleId) external;

/**
 * @dev Sets a single key-value pair in the oracle
 * @param oracleId Target oracle to update
 * @param key Data identifier (e.g., "BTC_PRICE", "DISCOUNT_RATE")
 * @param value Data value to store
 * @notice Only authorized invoker can update values
 * @notice Oracle must be active and registered
 */
function set(uint256 oracleId, bytes32 key, bytes32 value) external;

/**
 * @dev Sets multiple key-value pairs in a single transaction
 * @param oracleId Oracle instance to update
 * @param keys Array of data identifiers to update
 * @param values Array of corresponding values to store
 * @notice Arrays must be equal length
 * @notice All values must be valid
 * @notice More gas efficient than multiple single updates
 */
function setBatch(uint256 oracleId, bytes32[] memory keys, bytes32[] memory values) external;

/**
 * @dev Retrieves current value for a given key
 * @param oracleId Oracle to query
 * @param key Data point identifier
 * @return value Current stored value, 0x0 if not found
 * @return err Error message if lookup fails
 */
function get(uint256 oracleId, bytes32 key) external view returns (bytes32 value, string memory err);

/**
 * @dev Gets multiple values in a single call
 * @param oracleId Oracle to query
 * @param keys Array of data identifiers
 * @return values Array of current values
 * @return err Error message if any lookup fails
 */
function getBatch(uint256 oracleId, bytes32[] memory keys) external view returns (bytes32[] memory values, string memory err);

/**
 * @dev Emitted when a new oracle is added to the system
 * @param oracleId Identifier of the new oracle
 * @param invoker Address authorized to update oracle data
 */
event AddOracle(uint256 indexed oracleId, address invoker);

/**
 * @dev Emitted when an oracle is removed from the system
 * @param oracleId Identifier of the removed oracle
 */
event DeleteOracle(uint256 indexed oracleId);

/**
 * @dev Emitted when oracle data is updated
 * @param oracleId Oracle being updated
 * @param key Identifier of the data point
 * @param value New value being set
 */
event SetOracleValue(uint256 indexed oracleId, bytes32 key, bytes32 value);
}

/**
 * @title Transferable Interface
 * @dev Base interface for executing transfers between accounts
 */
interface ITransferable {
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
) external returns (bool result);

/**
 * @dev Emitted when a custom transfer is executed
 * @param sendAccountId Account that initiated the transfer
 * @param fromAccountId Source account of the funds
 * @param toAccountId Destination account
 * @param amount Amount of tokens transferred
 * @param miscValue1 First auxiliary value used in transfer
 * @param miscValue2 Second auxiliary value used in transfer
 */
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
 * @title Discount Interface
 * @dev Interface for managing discounts and price reductions
 */
interface IDiscount is ITransferable {
/**
 * @dev Emitted when a discount is applied to a purchase
 * @param sendAccountId Account receiving the discount
 * @param item Identifier of purchased item
 * @param amount Original price before discount
 * @param discountedAmount Final price after discount applied
 */
event Discount(bytes32 sendAccountId, bytes32 item, uint256 amount, uint256 discountedAmount);

/**
 * @dev Initializes discount contract with dependencies
 * @param oracle Oracle contract for price/discount data
 * @param token Token contract for payment handling
 * @notice Can only be called once during deployment
 * @notice Validates oracle and token addresses
 */
function initialize(IOracle oracle, ITransferable token) external;

/**
 * @dev Returns contract version for upgrades
 * @return Version string in semver format
 */
function version() external pure returns (string memory);

/**
 * @dev Updates oracle instance used for discounts
 * @param oracleId New oracle ID to use
 * @notice Only admin can update
 * @notice Validates oracle exists and is active
 */
function setOracleId(uint256 oracleId) external;

/**
 * @dev Gets current oracle ID
 * @return Currently active oracle identifier
 */
function getOracleId() external view returns (uint256);

/**
 * @dev Calculates discount based on purchase amount and history
 * @param amount Original purchase amount
 * @param purchasedCounts Number of previous purchases by account
 * @return Final discounted amount to charge
 * @notice Amount must be greater than 0
 * @notice Uses tiered discount rates based on purchase history
 */
function discount(uint256 amount, uint256 purchasedCounts) external pure returns (uint256);
}`;

            const systemPrompt = `You are a smart contract developer. Generate a complete implementation of the given interface. 

REQUIREMENTS:
1. Must implement ALL interface functions with EXACT signatures 
2. All function must have full code implementation and logic
3. Include comprehensive NatSpec documentation for ALL functions matching interface style
4. Must emit ALL events defined in the interface at appropriate points
5. Must match ALL parameter names and return values exactly
6. Create appropriate internal logic and helper functions
7. Use SafeMath for all arithmetic operations
8. Parameter validation requirements:
- Check for zero address where addresses are used
- Validate that amounts are greater than zero
- Verify array lengths match when multiple arrays are provided
- Ensure oracleId exists before operations
- Validate that accountIds are not empty (bytes32(0))
- Check if amounts don't exceed balances
9. Add proper validation checks with require statements and clear error messages
10. Include detailed error messages for each validation check
11. Follow memory/storage best practices for gas optimization
12. Generate at least 800 lines of detailed code while maintaining quality
13. Include events for all major state changes
14. Add access control for admin functions
15. Implement secure upgrade patterns if needed

INTERFACE TO IMPLEMENT:
${interfaceTemplate}

Generate only the implementation contract.
Do not include the interface definitions in your response.
Do not use markdown formatting.
Follow the exact NatSpec documentation style as shown in the interface.`;

            console.log('====+>', message, systemPrompt)

            const contractCode = await generateFullContract(message, systemPrompt);

            if (!contractCode) {
                return NextResponse.json(
                    { error: 'Failed to generate contract code' },
                    { status: 500 }
                );
            }

            return NextResponse.json({ contractCode });

        } else {
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

            const systemPrompt = `You are a smart contract developer. Generate a complete implementation based on the template and requirements.

Template:
${contractTemplate}

Requirements:
1. Follow OpenZeppelin's best practices
2. Include comprehensive NatSpec documentation for all functions
3. Implement all required features with complete logic
4. Add appropriate security measures and validations
5. Use clear naming conventions
6. Use SafeMath for calculations
7. Include events for state changes
8. Add access control
9. Follow gas optimization best practices
10. Include detailed error messages

Generate the complete contract implementation.
Do not use markdown formatting.
Include detailed implementation for all functions.`;

            console.log("=============>", message, systemPrompt);
            const contractCode = await generateWithBedrock(message, systemPrompt);

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