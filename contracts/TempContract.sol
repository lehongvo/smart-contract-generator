// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract RenewableEnergyTokenStorageLogic {
    // 定数の定義
    uint256 private constant MAX_LIMIT = 100;
    uint256 private constant EMPTY_LENGTH = 0;

    // トークンの状態を表す列挙型
    enum TokenStatus { Empty, Active, Locked }

    // トークンデータ構造
    struct RenewableEnergyTokenData {
        TokenStatus tokenStatus;
        bytes32 metadataId;
        bytes32 metadataHash;
        address owner;
        address previousOwner;
        bool isLocked;
        uint256 lastTransferTime;
        uint256 totalTransfers;
    }

    // マッピングの定義
    mapping(bytes32 => RenewableEnergyTokenData) private tokenData;
    mapping(address => bytes32[]) private tokensByOwner;

    // イベントの定義
    event TokenCreated(bytes32 indexed tokenId, address indexed owner);
    event TokenTransferred(bytes32 indexed tokenId, address indexed from, address indexed to);
    event TokenLocked(bytes32 indexed tokenId);
    event TokenUnlocked(bytes32 indexed tokenId);

    // トークン作成関数
    function createToken(bytes32 tokenId, bytes32 metadataId, bytes32 metadataHash) external {
        require(tokenData[tokenId].tokenStatus == TokenStatus.Empty, "Token already exists");
        
        tokenData[tokenId] = RenewableEnergyTokenData({
            tokenStatus: TokenStatus.Active,
            metadataId: metadataId,
            metadataHash: metadataHash,
            owner: msg.sender,
            previousOwner: address(0),
            isLocked: false,
            lastTransferTime: block.timestamp,
            totalTransfers: 0
        });
        
        tokensByOwner[msg.sender].push(tokenId);
        emit TokenCreated(tokenId, msg.sender);
    }

    // トークン転送関数
    function transferToken(bytes32 tokenId, address to) external {
        RenewableEnergyTokenData storage token = tokenData[tokenId];
        
        require(token.tokenStatus == TokenStatus.Active, "Token not active");
        require(!token.isLocked, "Token is locked");
        require(token.owner == msg.sender, "Not token owner");

        // 所有者情報の更新
        token.previousOwner = token.owner;
        token.owner = to;
        token.totalTransfers++;
        token.lastTransferTime = block.timestamp;

        // 所有者のトークンリストの更新
        _removeTokenFromOwner(msg.sender, tokenId);
        tokensByOwner[to].push(tokenId);
        
        emit TokenTransferred(tokenId, msg.sender, to);
    }

    // トークンロック関数
    function lockToken(bytes32 tokenId) external {
        RenewableEnergyTokenData storage token = tokenData[tokenId];
        
        require(token.owner == msg.sender, "Not token owner");
        require(!token.isLocked, "Token already locked");

        token.isLocked = true;
        emit TokenLocked(tokenId);
    }

    // トークンアンロック関数
    function unlockToken(bytes32 tokenId) external {
        RenewableEnergyTokenData storage token = tokenData[tokenId];

        require(token.owner == msg.sender, "Not token owner");
        require(token.isLocked, "Token is not locked");

        token.isLocked = false;
        emit TokenUnlocked(tokenId);
    }

    // 所有者のトークンリストからトークンを削除するヘルパー関数
    function _removeTokenFromOwner(address owner, bytes32 tokenId) internal {
        bytes32[] storage tokenIds = tokensByOwner[owner];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == tokenId) {
                tokenIds[i] = tokenIds[tokenIds.length - 1];
                tokenIds.pop();
                break;
            }
        }
    }

    // トークン情報を取得する関数
    function getTokenData(bytes32 tokenId) external view returns (RenewableEnergyTokenData memory) {
        return tokenData[tokenId];
    }

    // 所有者のトークンリストを取得する関数
    function getTokensByOwner(address owner) external view returns (bytes32[] memory) {
        return tokensByOwner[owner];
    }
}