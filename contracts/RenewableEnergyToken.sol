// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title RenewableEnergyToken
 * @dev A simple NFT contract for renewable energy tokens
 *
 * Features:
 * - Minting of unique tokens
 * - Transfer of tokens between owners
 * - Basic ownership management
 * - Token locking mechanism
 * - Blacklist functionality
 */
contract RenewableEnergyToken {
    // State variables
    struct TokenData {
        address owner;
        bool isLocked;
        string metadata;
    }

    // Mapping from token ID to token data
    mapping(uint256 => TokenData) private tokens;
    // Counter for the total number of tokens
    uint256 private tokenCounter;
    // Blacklist mapping
    mapping(address => bool) public blacklist;

    // Events
    event TokenMinted(uint256 indexed tokenId, address indexed owner, string metadata);
    event TokenTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    event TokenLocked(uint256 indexed tokenId);
    event TokenUnlocked(uint256 indexed tokenId);
    event AddressBlacklisted(address indexed account);
    event AddressWhitelisted(address indexed account);

    // Modifier to check if the address is blacklisted
    modifier notBlacklisted(address account) {
        require(!blacklist[account], "Address is blacklisted");
        _;
    }

    // Function to mint a new token
    function mint(string memory metadata) external notBlacklisted(msg.sender) {
        tokenCounter++;
        tokens[tokenCounter] = TokenData(msg.sender, false, metadata);
        emit TokenMinted(tokenCounter, msg.sender, metadata);
    }

    // Function to transfer token ownership
    function transfer(uint256 tokenId, address to) external notBlacklisted(msg.sender) {
        require(tokens[tokenId].owner == msg.sender, "Not the token owner");
        require(!tokens[tokenId].isLocked, "Token is locked");
        require(to != address(0), "Invalid address");

        tokens[tokenId].owner = to;
        emit TokenTransferred(tokenId, msg.sender, to);
    }

    // Function to lock a token
    function lockToken(uint256 tokenId) external {
        require(tokens[tokenId].owner == msg.sender, "Not the token owner");
        tokens[tokenId].isLocked = true;
        emit TokenLocked(tokenId);
    }

    // Function to unlock a token
    function unlockToken(uint256 tokenId) external {
        require(tokens[tokenId].owner == msg.sender, "Not the token owner");
        tokens[tokenId].isLocked = false;
        emit TokenUnlocked(tokenId);
    }

    // Function to blacklist an address
    function blacklistAddress(address account) external {
        blacklist[account] = true;
        emit AddressBlacklisted(account);
    }

    // Function to whitelist an address
    function whitelistAddress(address account) external {
        blacklist[account] = false;
        emit AddressWhitelisted(account);
    }

    // Function to get token details
    function getToken(uint256 tokenId) external view returns (address owner, bool isLocked, string memory metadata) {
        TokenData memory token = tokens[tokenId];
        return (token.owner, token.isLocked, token.metadata);
    }
}