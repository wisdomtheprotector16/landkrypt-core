// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LandKryptStakingToken is ERC20, Ownable {
    constructor() ERC20("LandKrypt Staking Token", "LKST") {}

    // Mint LKST tokens (only callable by the staking contract)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Burn LKST tokens (only callable by the DAO contract)
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}