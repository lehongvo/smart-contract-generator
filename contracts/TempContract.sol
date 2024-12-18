// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// TempContract is a simple ERC20 token contract
contract TempContract is ERC20 {
    // Constructor to initialize the ERC20 token with name 'A' and symbol 'B'
    constructor() ERC20("A", "B") {
        _mint(msg.sender, 1000 * (10 ** uint256(decimals())));
    }
}