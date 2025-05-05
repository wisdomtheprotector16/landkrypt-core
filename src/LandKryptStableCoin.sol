// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/access/Ownable.sol";

contract LandKryptStablecoin is ERC20, Ownable {
    constructor() ERC20("LandKrypt Stablecoin", "LKUSD") {}

    // Mint stablecoins (only callable by the NFT Marketplace)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Burn stablecoins (only callable by the NFT Marketplace)
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}