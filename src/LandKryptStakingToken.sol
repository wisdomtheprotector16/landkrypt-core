// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LandKryptStakingToken is ERC20, Ownable {
    // Mapping to track allowed minters
    mapping(address => bool) private _minters;
    // Mapping to track allowed burners
    mapping(address => bool) private _burners;
    // Arrays to track all minters/burners (for management)
    address[] private _minterList;
    address[] private _burnerList;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event BurnerAdded(address indexed account);
    event BurnerRemoved(address indexed account);

    constructor() ERC20("LandKrypt Staking Token", "LKST") {}

    /**
     * @dev Throws if called by any account that's not a minter.
     */
    modifier onlyMinter() {
        require(_minters[msg.sender], "LandKryptStakingToken: caller is not a minter");
        _;
    }

    /**
     * @dev Throws if called by any account that's not a burner.
     */
    modifier onlyBurner() {
        require(_burners[msg.sender], "LandKryptStakingToken: caller is not a burner");
        _;
    }

    /**
     * @dev Add an address to the minter allowlist
     * @param account The address to add as a minter
     */
    function addMinter(address account) external onlyOwner {
        require(account != address(0), "LandKryptStakingToken: zero address cannot be minter");
        require(!_minters[account], "LandKryptStakingToken: address is already minter");
        
        _minters[account] = true;
        _minterList.push(account);
        emit MinterAdded(account);
    }

    /**
     * @dev Remove an address from the minter allowlist
     * @param account The address to remove as a minter
     */
    function removeMinter(address account) external onlyOwner {
        require(_minters[account], "LandKryptStakingToken: address is not minter");
        
        _minters[account] = false;
        
        // Remove from minterList array
        for (uint256 i = 0; i < _minterList.length; i++) {
            if (_minterList[i] == account) {
                _minterList[i] = _minterList[_minterList.length - 1];
                _minterList.pop();
                break;
            }
        }
        
        emit MinterRemoved(account);
    }

    /**
     * @dev Add an address to the burner allowlist
     * @param account The address to add as a burner
     */
    function addBurner(address account) external onlyOwner {
        require(account != address(0), "LandKryptStakingToken: zero address cannot be burner");
        require(!_burners[account], "LandKryptStakingToken: address is already burner");
        
        _burners[account] = true;
        _burnerList.push(account);
        emit BurnerAdded(account);
    }

    /**
     * @dev Remove an address from the burner allowlist
     * @param account The address to remove as a burner
     */
    function removeBurner(address account) external onlyOwner {
        require(_burners[account], "LandKryptStakingToken: address is not burner");
        
        _burners[account] = false;
        
        // Remove from burnerList array
        for (uint256 i = 0; i < _burnerList.length; i++) {
            if (_burnerList[i] == account) {
                _burnerList[i] = _burnerList[_burnerList.length - 1];
                _burnerList.pop();
                break;
            }
        }
        
        emit BurnerRemoved(account);
    }

    /**
     * @dev Check if an address is allowed to mint
     * @param account The address to check
     * @return bool Whether the address is a minter
     */
    function isMinter(address account) external view returns (bool) {
        return _minters[account];
    }

    /**
     * @dev Check if an address is allowed to burn
     * @param account The address to check
     * @return bool Whether the address is a burner
     */
    function isBurner(address account) external view returns (bool) {
        return _burners[account];
    }

    /**
     * @dev Get list of all allowed minters
     * @return address[] memory Array of minter addresses
     */
    function getAllMinters() external view returns (address[] memory) {
        return _minterList;
    }

    /**
     * @dev Get list of all allowed burners
     * @return address[] memory Array of burner addresses
     */
    function getAllBurners() external view returns (address[] memory) {
        return _burnerList;
    }

    /**
     * @dev Mint LKST tokens (only callable by allowed minters)
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /**
     * @dev Burn LKST tokens (only callable by allowed burners)
     * @param from The address whose tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyBurner {
        _burn(from, amount);
    }
}