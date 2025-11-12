// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleToken is ERC20 {
    // Initialize contract with 1 million tokens minted to the creator of the contract
    constructor() ERC20("Simple Token", "SIMPLE") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}
