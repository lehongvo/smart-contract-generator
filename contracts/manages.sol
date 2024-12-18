// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title RenewableEnergyTokenStorageLogic
 * @dev Implementation of a renewable energy token storage contract
 *
 * This contract manages the storage and operations of renewable energy tokens.
 *
 * Features:
 * - Token minting and burning
 * - Ownership tracking
 * - Access control for admin functions
 * - Event logging for all important actions
 * - Rate limiting for sensitive operations
 */
contract RenewableEnergyTokenStorageLogic {
    enum TokenStatus { Active, Burned }

    struct RenewableEnergyTokenData {
        TokenStatus status;
        address owner;
        bytes32 metadataId;
        bytes32 metadataHash;
        uint256 lastTransferTime; // For rate limiting
    }

    mapping(bytes32 => RenewableEnergyTokenData) private tokens;
    mapping(address => bytes32[]) private tokensByOwner;
    mapping(address => bool) private admins;

    event TokenMinted(bytes32 indexed tokenId, address indexed owner, bytes32 metadataId, bytes32 metadataHash);
    event TokenBurned(bytes32 indexed tokenId);
    event OwnershipTransferred(bytes32 indexed tokenId, address indexed from, address indexed to);

    modifier onlyAdmin() {
        require(admins[msg.sender], "Not an admin");
        _;
    }

    modifier rateLimited(bytes32 tokenId) {
        require(block.timestamp >= tokens[tokenId].lastTransferTime + 1 days, "Rate limit: Too many transfers");
        _;
        tokens[tokenId].lastTransferTime = block.timestamp;
    }

    constructor() {
        admins[msg.sender] = true; // Assign deployer as the initial admin
    }

    function mintToken(bytes32 tokenId, bytes32 metadataId, bytes32 metadataHash) external onlyAdmin {
        require(tokens[tokenId].status != TokenStatus.Active, "Token already exists");
        tokens[tokenId] = RenewableEnergyTokenData(TokenStatus.Active, msg.sender, metadataId, metadataHash, block.timestamp);
        tokensByOwner[msg.sender].push(tokenId);
        
        emit TokenMinted(tokenId, msg.sender, metadataId, metadataHash);
    }

    function burnToken(bytes32 tokenId) external {
        require(tokens[tokenId].status == TokenStatus.Active, "Token not active");
        require(tokens[tokenId].owner == msg.sender, "Not the token owner");

        tokens[tokenId].status = TokenStatus.Burned;
        emit TokenBurned(tokenId);
    }

    function transferOwnership(bytes32 tokenId, address newOwner) external rateLimited(tokenId) {
        require(tokens[tokenId].status == TokenStatus.Active, "Token not active");
        require(tokens[tokenId].owner == msg.sender, "Not the token owner");

        tokens[tokenId].owner = newOwner;
        emit OwnershipTransferred(tokenId, msg.sender, newOwner);
    }

    function addAdmin(address account) external onlyAdmin {
        admins[account] = true;
    }

    function removeAdmin(address account) external onlyAdmin {
        admins[account] = false;
    }

    function getTokenData(bytes32 tokenId) external view returns (TokenStatus, address, bytes32, bytes32) {
        RenewableEnergyTokenData storage token = tokens[tokenId];
        return (token.status, token.owner, token.metadataId, token.metadataHash);
    }

    function getTokensByOwner(address owner) external view returns (bytes32[] memory) {
        return tokensByOwner[owner];
    }
}