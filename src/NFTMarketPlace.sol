// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RealEstateNFT.sol";
import "./LandKryptStablecoin.sol";
import "./NFTDAO.sol"; // Import NFTDAO to call recordNFTPurchaseTime

contract NFTMarketplace {
    RealEstateNFT public nftContract;
    LandKryptStablecoin public stablecoin;
    address public owner;
    NFTDAO public nftDAO; // Reference to the NFTDAO contract

    struct Listing {
        uint256 price;
        address stakingContract;
        bool isListed;
    }

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => uint256) public earnings;
    mapping(uint256 => bool) public listedBool;

    event NFTListed(uint256 tokenId, uint256 price, address stakingContract);
    event NFTPurchased(uint256 tokenId, address buyer);
    event EarningsWithdrawn(uint256 tokenId, uint256 amount);
    event StablecoinMinted(uint256 tokenId, uint256 amount);
    event StablecoinBurned(uint256 tokenId, uint256 amount);

    constructor(address _nftContract, address _stablecoin, address _nftDAO) {
        nftContract = RealEstateNFT(_nftContract);
        stablecoin = LandKryptStablecoin(_stablecoin);
        owner = msg.sender;
        nftDAO = NFTDAO(_nftDAO); // Initialize NFTDAO
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // List an NFT, mint stablecoins, and assign a staking contract
    function listNFT(uint256 tokenId, uint256 price, address stakingContract) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Only owner can list NFT");
        require(stakingContract.tokenId() == tokenId, "Staking contract must have been deployed for this ID");
        require(!listedBool[tokenId], "NFT is already listed");

        listings[tokenId] = Listing(price, stakingContract, true);

        // Mint stablecoins at 135% of the NFT price
        uint256 stablecoinAmount = (price * 135) / 100;
        stablecoin.mint(address(this), stablecoinAmount);
        listedBool[tokenId] = true;

        emit NFTListed(tokenId, price, stakingContract);
        emit StablecoinMinted(tokenId, stablecoinAmount);
    }

    // Only the assigned staking contract can buy the NFT
    function buyNFT(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.isListed, "NFT is not listed");
        require(msg.sender == listing.stakingContract, "Only assigned staking contract can buy");

        // Transfer NFT from marketplace to staking contract
        nftContract.transferFrom(nftContract.ownerOf(tokenId), listing.stakingContract, tokenId);

        // Record earnings
        earnings[tokenId] += listing.price;

        // Record NFT purchase time in NFTDAO
        nftDAO.recordNFTPurchaseTime(tokenId);

        // Remove listing
        delete listings[tokenId];
        emit NFTPurchased(tokenId, msg.sender);
    }

    // Relist to change price of listing
    function relistNFT(uint256 tokenId, uint256 newPrice) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Only NFT owner can resell");
        require(listings[tokenId].isListed, "NFT is not listed");

        // Burn stablecoins at 135% of the NFT price
        uint256 stablecoinAmount = (listings[tokenId].price * 135) / 100;
        stablecoin.burn(address(this), stablecoinAmount);

        listings[tokenId] = Listing(newPrice, msg.sender, true);

        // Mint stablecoins at 115% of the new price
        stablecoinAmount = (newPrice * 115) / 100;
        stablecoin.mint(address(this), stablecoinAmount);

        emit NFTListed(tokenId, newPrice, msg.sender);
        emit StablecoinMinted(tokenId, stablecoinAmount);
    }

    // Withdraw earnings from a sold NFT
    function withdrawEarnings(uint256 tokenId) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Only owner can withdraw");
        uint256 amount = earnings[tokenId];
        require(amount > 0, "No earnings to withdraw");

        earnings[tokenId] = 0;
        payable(msg.sender).transfer(amount);
        emit EarningsWithdrawn(tokenId, amount);
    }

    // Delete a listing (only owner)
    function deleteListing(uint256 tokenId) external {
        require(listings[tokenId].isListed, "NFT is not listed");
        require(nftContract.ownerOf(tokenId) == msg.sender, "Only owner can delete listing");

        // Burn stablecoins at 135% of the NFT price
        uint256 stablecoinAmount = (listings[tokenId].price * 135) / 100;
        stablecoin.burn(address(this), stablecoinAmount);

        delete listings[tokenId];
        emit StablecoinBurned(tokenId, stablecoinAmount);
    }
}