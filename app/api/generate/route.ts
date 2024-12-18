import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

// Định nghĩa interface cho input
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

/**
 * @title ${input.name || 'Token'}
 * @dev Implementation of the ${input.name || 'Token'} with enhanced security and features
 *
 * Security Features:
 * - Reentrancy protection using ReentrancyGuard
 * - SafeMath for arithmetic operations
 * - Role-based access control
 * - Emergency pause capabilities
 * - Blacklist/Whitelist system
 * - Rate limiting for transactions
 *
 * Tokenomics:
 * - Dynamic tax mechanism
 * - Anti-bot measures
 * - Auto-liquidity generation
 * - Holder rewards
 * - Vesting schedules
 * - Max wallet limits
 * - Buyback and burn
 *
 * Advanced Features:
 * - Governance system
 * - Staking mechanism
 * - Token locking
 * - Multi-signature support
 * - Cross-chain capabilities
 * - Batch transfers
 */
/**
 * @title ${input.name || 'Token'}
 * @dev Implementation of the ${input.name || 'Token'} with enhanced security and features
 */
contract ${input.name || 'TempContract'} is ${this.getInheritance(input)} {
    using SafeMath for uint256;

    // Constants & Roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 private constant MAX_TAX = 2500; // 25%
    uint256 private constant MAX_WALLET_LIMIT = 100000 * 10**18; // 100,000 tokens
    uint256 private constant COOLDOWN_TIME = 30 seconds;
    
    // Events
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event Blacklisted(address indexed account);
    event TaxesUpdated(uint256 buyTax, uint256 sellTax, uint256 transferTax);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount);
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event Locked(address indexed account, uint256 amount, uint256 duration);
    event GovernanceVote(uint256 indexed proposalId, address indexed voter);
    event TokenTransferred(address indexed from, address indexed to, uint256 amount);
    event WhitelistUpdated(address indexed account, bool status);
    event WhitelistStatusChanged(bool enabled);
    
    // Role-based Access Control
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    // Core mappings
    mapping(address => bool) public blacklisted;
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) private lastTransactionTime;
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public vestingBalance;
    
    uint256 public buyTax;
    uint256 public sellTax;
    uint256 public transferTax;
    uint256 public liquidityFee;
    bool public tradingEnabled;
    bool public whitelistEnabled;

    function _grantRole(bytes32 role, address account) internal {
        _roles[role][account] = true;
        emit RoleGranted(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal {
        _roles[role][account] = false;
        emit RoleRevoked(role, account);
    }

    modifier tradingOpen() {
        require(tradingEnabled || msg.sender == owner(), "Trading not enabled");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Address is blacklisted");
        _;
    }

    modifier rateLimited() {
        require(
            block.timestamp >= lastTransactionTime[msg.sender].add(COOLDOWN_TIME),
            "Rate limited"
        );
        _;
        lastTransactionTime[msg.sender] = block.timestamp;
    }

    constructor(address initialOwner)
        ${this.getConstructorCalls(input)}
    {
        // Initialize features
        buyTax = 500;  // 5%
        sellTax = 500; // 5%
        transferTax = 200; // 2%
        liquidityFee = 300; // 3%
        whitelistEnabled = true;
        
        // Grant initial roles
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(OPERATOR_ROLE, initialOwner);
    }

    // Core functions with SafeMath
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        uint256 fee = amount.mul(transferTax).div(10000);
        uint256 netAmount = amount.sub(fee);
        
        super._transfer(from, to, netAmount);
        if (fee > 0) {
            super._transfer(from, address(this), fee);
        }
        
        emit TokenTransferred(from, to, amount);
    }

    ${this.getCoreFunctions(input)}
    ${this.getSecurityFunctions()}
    ${this.getTokenomicsFunctions()}
    ${this.getAdvancedFunctions()}
    ${this.getOverrideFunctions(input)}
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

        if (input.features?.tokenomics?.buybackBurn) {
            imports.push('import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";');
        }

        if (input.features?.advanced?.governance) {
            imports.push('import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";');
            imports.push('import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";');
            imports.push('import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";');
        }

        return imports.join('\n');
    }

    private getInheritance(input: ContractInput): string {
        const inheritance = ['ERC20', 'Ownable', 'ReentrancyGuard'];

        if (input.features?.security?.pausable) inheritance.push('Pausable');
        if (input.features?.tokenomics?.buybackBurn) inheritance.push('ERC20Burnable');
        if (input.features?.advanced?.governance) {
            inheritance.push('ERC20Permit');
            inheritance.push('ERC20Votes');
        }

        return inheritance.join(', ');
    }

    private getConstructorCalls(input: ContractInput): string {
        const calls = [
            `ERC20("${input.name || 'TempContract'}", "${input.name ? input.name.substring(0, 3).toUpperCase() : 'TMP'}")`,
            'Ownable(initialOwner)',
            'ReentrancyGuard()'
        ];

        if (input.features?.advanced?.governance) {
            calls.push(`ERC20Permit("${input.name || 'TempContract'}")`);
        }

        return calls.join(',\n        ');
    }

    private getSecurityFunctions(): string {
        return `
    function setBlacklist(address account, bool status) external onlyOwner {
        blacklisted[account] = status;
        emit Blacklisted(account);
    }

    function setWhitelist(address account, bool status) external onlyOwner {
        whitelisted[account] = status;
    }

    function setWhitelistEnabled(bool enabled) external onlyOwner {
        whitelistEnabled = enabled;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }`;
    }

    private getTokenomicsFunctions(): string {
        return `
    function setTaxes(uint256 _buyTax, uint256 _sellTax, uint256 _transferTax) external onlyOwner {
        require(_buyTax <= MAX_TAX && _sellTax <= MAX_TAX && _transferTax <= MAX_TAX, "Tax too high");
        buyTax = _buyTax;
        sellTax = _sellTax;
        transferTax = _transferTax;
        emit TaxesUpdated(_buyTax, _sellTax, _transferTax);
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
    }

    function addLiquidity() external payable onlyOwner {
        uint256 tokenAmount = balanceOf(address(this));
        // Add liquidity logic here
        emit LiquidityAdded(tokenAmount, msg.value);
    }`;
    }

    private getAdvancedFunctions(): string {
        return `
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] = stakedBalance[msg.sender].add(amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient stake");
        stakedBalance[msg.sender] = stakedBalance[msg.sender].sub(amount);
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function lockTokens(uint256 amount, uint256 duration) external {
        require(amount > 0, "Cannot lock 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        // Locking logic here
        emit Locked(msg.sender, amount, duration);
    }`;
    }

    private getCoreFunctions(input: ContractInput): string {
        const functions = [];

        if (input.features?.security?.pausable) {
            functions.push(`
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }`);
        }

        if (input.features?.tokenomics?.buybackBurn || input.features?.tokenomics?.rewardSystem) {
            functions.push(`
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }`);
        }

        if (input.features?.advanced?.governance) {
            functions.push(`
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }`);
        }

        return functions.join('\n');
    }

    private getOverrideFunctions(input: ContractInput): string {
        const functions = [];

        const updateInheritance = ['ERC20'];
        if (input.features?.security?.pausable) updateInheritance.push('Pausable');
        if (input.features?.advanced?.governance) updateInheritance.push('ERC20Votes');

        if (updateInheritance.length > 1) {
            functions.push(`
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(${updateInheritance.join(', ')}) {
        super._update(from, to, value);
    }`);
        }

        if (input.features?.advanced?.governance) {
            functions.push(`
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }`);
        }

        return functions.join('\n');
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

        let contractInput: ContractInput;
        try {
            contractInput = JSON.parse(message);
        } catch {
            contractInput = {
                name: "TempContract",
                type: "ERC20"
            };
        }

        const generator = new OpenZeppelinStyleGenerator();
        const contractTemplate = generator.getContractTemplate(contractInput);

        const getFeatureDescription = (input: ContractInput) => {
            const features = [];

            if (input.features?.security) {
                const security = input.features.security;
                if (security.reentrancy) features.push("- Enhanced reentrancy protection");
                if (security.accessControl) features.push("- Advanced role-based access control");
                if (security.pausable) features.push("- Emergency pause functionality");
                if (security.blacklist) features.push("- Blacklist system");
                if (security.whitelist) features.push("- Whitelist mechanism");
                if (security.rateLimiting) features.push("- Transaction rate limiting");
            }

            if (input.features?.tokenomics) {
                const tokenomics = input.features.tokenomics;
                if (tokenomics.dynamicTax) features.push("- Dynamic tax system");
                if (tokenomics.antiBot) features.push("- Anti-bot mechanisms");
                if (tokenomics.autoLiquidity) features.push("- Automatic liquidity generation");
                if (tokenomics.rewardSystem) features.push("- Holder rewards system");
                if (tokenomics.vesting) features.push("- Token vesting schedules");
                if (tokenomics.maxWalletLimit) features.push("- Maximum wallet holdings");
                if (tokenomics.buybackBurn) features.push("- Buyback and burn mechanism");
            }

            if (input.features?.advanced) {
                const advanced = input.features.advanced;
                if (advanced.governance) features.push("- Governance functionality");
                if (advanced.staking) features.push("- Staking mechanism");
                if (advanced.tokenLocking) features.push("- Token locking system");
                if (advanced.multiSig) features.push("- Multi-signature requirements");
                if (advanced.crossChain) features.push("- Cross-chain support");
                if (advanced.batchTransfer) features.push("- Batch transfer capabilities");
            }

            return features.join("\n");
        };

        const completion = await openai.chat.completions.create({
            model: "gpt-3.5-turbo",
            messages: [
                {
                    role: "system",
                    content: `You are an expert Solidity smart contract generator and auditor. Never use markdown formatting or code block syntax.
        Example structure to follow:
        ${contractTemplate}
        
        Generate advanced, secure contracts with these enterprise-level features:
        
        SECURITY FEATURES:
        - Reentrancy guards for all external calls
        - Integer overflow protection using SafeMath
        - Access control with role-based permissions
        - Emergency pause mechanisms
        - Blacklist and whitelist functionalities
        - Rate limiting for transactions
        
        TOKENOMICS AND FEATURES:
        - Dynamic tax system (buy/sell/transfer taxes)
        - Anti-bot and anti-snipe mechanisms 
        - Auto liquidity generation
        - Reflection rewards to holders
        - Vesting schedules for team/presale tokens
        - Max wallet and transaction limits
        - Token buyback and burn mechanisms
        - Flash loan attack prevention
        
        ADVANCED FUNCTIONS:
        - Governance integration
        - Staking capabilities
        - Token locking
        - Multi-signature requirements
        - Upgradeability patterns
        - Cross-chain bridge support
        - Batch transfer capabilities
        
        OPTIMIZATION:
        - Gas-optimized code patterns
        - Efficient storage layouts
        - Minimal external calls
        - Optimized loops and arrays
        
        FORMAT:
        - Comprehensive NatSpec documentation
        - Clear function grouping
        - Extensive event logging
        - Security-focused modifiers
        - Detailed error messages

        IMPLEMENTATION PATTERNS FROM RENEWABLE ENERGY TOKEN:

        1. CONSTANT DEFINITIONS AND STORAGE PATTERNS:
        {
            // Maximum limit for pagination
            uint256 private constant _MAX_LIMIT = 100;
            
            // Empty length constant for unregistered cases
            uint256 private constant _EMPTY_LENGTH = 0;
            
            // Fixed values for external signature verification
            bytes32 private constant _STRING_TRANSFER = "transfer";
            
            // Sort control fixed values
            bytes32 private constant _DESC_SORT = keccak256(bytes("desc"));
            bytes32 private constant _ASC_SORT = keccak256(bytes("asc"));
        }

        2. TOKEN DATA STRUCTURES AND MAPPING:
        {
            struct RenewableEnergyTokenData {
                TokenStatus tokenStatus;
                bytes32 metadataId;
                bytes32 metadataHash;
                bytes32 mintAccountId;
                bytes32 ownerAccountId;
                bytes32 previousAccountId;
                bool isLocked;
            }
            
            mapping(bytes32 => RenewableEnergyTokenData) private renewableEnergyTokenData;
            mapping(bytes32 => bytes32[]) private tokenIdsByAccountId;
        }

        3. PAGINATION AND LIST MANAGEMENT:
        {
            function getTokenList(
                mapping(bytes32 => RenewableEnergyTokenData) storage data,
                bytes32[] storage tokenIds,
                bytes32 accountId,
                uint256 offset,
                uint256 limit
            ) external view returns (TokenListData[] memory list, uint256 total, string memory err) {
                // Validate limits
                if (limit == 0 || limit > _MAX_LIMIT) {
                    return (list, _EMPTY_LENGTH, "Invalid limit");
                }
                
                // Count matching tokens
                uint256 tokenCount = 0;
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    if (data[tokenIds[i]].ownerAccountId == accountId) {
                        tokenCount++;
                    }
                }
                
                // Handle offset validation
                if (offset >= tokenCount) {
                    return (list, tokenCount, "Offset out of bounds");
                }
                
                // Calculate actual size based on remaining items
                uint256 size = (tokenCount >= offset + limit) ? limit : tokenCount - offset;
                list = new TokenListData[](size);
                
                // Fill the list with data
                uint256 index = 0;
                for (uint256 i = offset; i < offset + size; i++) {
                    // Copy token data to list
                }
                
                return (list, tokenCount, "");
            }
        }

        4. SECURE TOKEN TRANSFER WITH VALIDATION:
        {
            function transferToken(
                mapping(bytes32 => RenewableEnergyTokenData) storage tokenData,
                mapping(bytes32 => bytes32[]) storage tokenIdsByAccountId,
                bytes32 tokenId,
                bytes32 fromAccountId,
                bytes32 toAccountId
            ) external {
                // Validate token state
                require(tokenData[tokenId].tokenStatus == TokenStatus.Active, "Token not active");
                require(!tokenData[tokenId].isLocked, "Token is locked");
                require(tokenData[tokenId].ownerAccountId == fromAccountId, "Not token owner");
                
                // Remove token from sender
                for (uint256 i = 0; i < tokenIdsByAccountId[fromAccountId].length; i++) {
                    if (tokenIdsByAccountId[fromAccountId][i] == tokenId) {
                        // Move last element to current position and pop
                        tokenIdsByAccountId[fromAccountId][i] = tokenIdsByAccountId[fromAccountId][
                            tokenIdsByAccountId[fromAccountId].length - 1
                        ];
                        tokenIdsByAccountId[fromAccountId].pop();
                        break;
                    }
                }
                
                // Update ownership
                tokenData[tokenId].ownerAccountId = toAccountId;
                tokenData[tokenId].previousAccountId = fromAccountId;
                
                // Add token to receiver
                tokenIdsByAccountId[toAccountId].push(tokenId);
            }
        }

        5. BATCH OPERATIONS WITH SAFETY CHECKS:
        {
            function transferBatchTokens(
                mapping(bytes32 => RenewableEnergyTokenData) storage tokenData,
                mapping(bytes32 => bytes32[]) storage tokenIdsByAccountId,
                string[] memory tokenIds,
                bytes32 fromAccountId,
                bytes32 toAccountId
            ) external {
                for (uint256 i; i < tokenIds.length; i++) {
                    bytes32 tokenId = stringToBytes32(tokenIds[i]);
                    
                    // Validate each token
                    require(tokenData[tokenId].tokenStatus == TokenStatus.Active, "Token not active");
                    require(!tokenData[tokenId].isLocked, "Token is locked");
                    require(tokenData[tokenId].ownerAccountId == fromAccountId, "Not token owner");
                    
                    // Perform transfer logic for each token
                    // [Transfer implementation as shown in single transfer]
                }
            }
        }

        6. SECURE STORAGE AND CONSTANT PATTERNS:
        {
            // Use SafeMath for all arithmetic operations
            using SafeMathUpgradeable for uint256;
            
            // Define clear constants for limits and configurations
            uint256 private constant _MAX_LIMIT = 100;
            uint256 private constant _EMPTY_LENGTH = 0;
            
            // Use keccak256 for deterministic values
            bytes32 private constant _TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
            bytes32 private constant _ADMIN_ROLE = keccak256("ADMIN_ROLE");
            
            // Efficient status tracking
            enum TokenStatus { Empty, Active, Locked }
            
            // Error messages as constants
            string private constant ERROR_TOKEN_LOCKED = "Token is locked";
            string private constant ERROR_NOT_OWNER = "Not token owner";
        }

        7. COMPREHENSIVE TOKEN DATA STRUCTURE:
        {
            struct TokenData {
                TokenStatus status;
                bytes32 metadataId;
                bytes32 metadataHash;
                bytes32 mintAccountId;
                bytes32 ownerAccountId;
                bytes32 previousAccountId;
                bool isLocked;
                uint256 lastTransferTime;    // For rate limiting
                uint256 totalTransfers;      // For tracking
            }
            
            // Efficient mappings
            mapping(bytes32 => TokenData) private tokenData;
            mapping(bytes32 => bytes32[]) private tokensByAccount;
            mapping(bytes32 => bool) private blacklist;
            mapping(bytes32 => bool) private whitelist;
        }

        8. SECURITY AND ACCESS CONTROL:
        {
            // Reentrancy protection
            uint256 private _guardCounter;
            modifier nonReentrant() {
                _guardCounter += 1;
                uint256 localCounter = _guardCounter;
                _;
                require(localCounter == _guardCounter, "ReentrancyGuard: reentrant call");
            }
            
            // Rate limiting
            modifier rateLimited(bytes32 tokenId) {
                require(
                    block.timestamp >= tokenData[tokenId].lastTransferTime,
                    "Rate limit: Too many transfers"
                );
                _;
                tokenData[tokenId].lastTransferTime = block.timestamp;
            }
            
        }

        9. EFFICIENT TRANSFER MECHANISMS:
        {
            function transferToken(
                bytes32 tokenId,
                bytes32 fromAccount,
                bytes32 toAccount
            ) external nonReentrant rateLimited(tokenId) {
                // Validate states
                require(tokenData[tokenId].status == TokenStatus.Active, "Token not active");
                require(!tokenData[tokenId].isLocked, ERROR_TOKEN_LOCKED);
                require(!blacklist[toAccount], "Recipient blacklisted");
                require(whitelist[toAccount] || !whitelistEnabled, "Recipient not whitelisted");
                
                // Update ownership with gas optimization
                _removeTokenFromAccount(fromAccount, tokenId);
                _addTokenToAccount(toAccount, tokenId);
                
                // Update token data
                tokenData[tokenId].previousAccountId = fromAccount;
                tokenData[tokenId].ownerAccountId = toAccount;
                tokenData[tokenId].totalTransfers++;
                
                emit TokenTransferred(tokenId, fromAccount, toAccount);
            }
        }

        10. BATCH OPERATIONS WITH SAFETY:
        {
            function batchTransfer(
                bytes32[] calldata tokenIds,
                bytes32 fromAccount,
                bytes32 toAccount
            ) external nonReentrant {
                require(tokenIds.length <= _MAX_BATCH_SIZE, "Batch too large");
                
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    // Validate each token
                    _validateTransfer(tokenIds[i], fromAccount, toAccount);
                    
                    // Perform transfer
                    _transferSingle(tokenIds[i], fromAccount, toAccount);
                }
                
                emit BatchTransferred(tokenIds, fromAccount, toAccount);
            }
        }
        
        REQUESTED FEATURES:
        ${getFeatureDescription(contractInput)}
        
        The contract must:
        - Be named '${contractInput.name || 'TempContract'}'
        - Extend OpenZeppelin's ${contractInput.type || 'ERC20'} based on the requirement
        - Include clear inline documentation
        - Follow latest Solidity best practices
        - Constructor should NOT accept parameters like 'name' or 'symbol'
        - Use fixed constants 'A' and 'B' instead of constructor parameters`
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

    } catch (error) {
        console.error('Error:', error);
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}