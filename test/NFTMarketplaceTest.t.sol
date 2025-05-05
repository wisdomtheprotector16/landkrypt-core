// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/NFTMarketplace.sol";
import "../contracts/RealEstateNFT.sol";
import "../contracts/LandKryptStablecoin.sol";
import "../contracts/NFTDAO.sol";
import "../contracts/NFTStaking.sol";

contract NFTMarketplaceTest is Test {
    NFTMarketplace public marketplace;
    RealEstateNFT public nftContract;
    LandKryptStablecoin public stablecoin;
    NFTDAO public nftDAO;
    
    address owner = address(0x1);
    address nftOwner = address(0x2);
    address otherAccount = address(0x3);
    
    uint256 tokenId = 1;
    uint256 price = 1000 ether;
    uint256 newPrice = 1200 ether;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy dependencies
        nftContract = new RealEstateNFT();
        stablecoin = new LandKryptStablecoin();
        nftDAO = new NFTDAO();
        
        // Deploy marketplace
        marketplace = new NFTMarketplace(
            address(nftContract),
            address(stablecoin),
            address(nftDAO)
        );
        
        // Mint NFT to test owner
        nftContract.mint(nftOwner, tokenId);
        vm.stopPrank();
    }

    // ============ Deployment Tests ============
    function testDeployment() public {
        assertEq(marketplace.owner(), owner, "Owner should be set correctly");
        assertEq(address(marketplace.nftContract()), address(nftContract), "NFT contract address mismatch");
        assertEq(address(marketplace.stablecoin()), address(stablecoin), "Stablecoin address mismatch");
        assertEq(address(marketplace.nftDAO()), address(nftDAO), "NFTDAO address mismatch");
    }

    // ============ Listing Tests ============
    function testListNFT() public {
        // Deploy a staking contract for this test
        vm.startPrank(owner);
        NFTStaking stakingContract = new NFTStaking(
            address(marketplace),
            address(stablecoin),
            address(0), // stakingToken
            address(0), // developmentContract
            tokenId,
            price,
            address(nftContract),
            owner
        );
        vm.stopPrank();

        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        
        vm.expectEmit(true, true, true, true);
        emit NFTListed(tokenId, price, address(stakingContract));
        
        marketplace.listNFT(tokenId, price, address(stakingContract));
        vm.stopPrank();

        // Verify listing
        (uint256 listedPrice, address stakingAddr, bool isListed) = marketplace.listings(tokenId);
        assertEq(listedPrice, price, "Price not set correctly");
        assertEq(stakingAddr, address(stakingContract), "Staking contract not set correctly");
        assertTrue(isListed, "NFT not marked as listed");
        assertTrue(marketplace.listedBool(tokenId), "Listed bool not set");
        
        // Verify stablecoin minting (135% of price)
        uint256 expectedStablecoins = (price * 135) / 100;
        assertEq(stablecoin.balanceOf(address(marketplace)), expectedStablecoins, "Stablecoins not minted correctly");
    }

    function testListNFTFailsIfNotOwner() public {
        vm.startPrank(otherAccount);
        vm.expectRevert("Only owner can list NFT");
        marketplace.listNFT(tokenId, price, address(0));
        vm.stopPrank();
    }

    function testListNFTFailsIfAlreadyListed() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(0));
        
        vm.expectRevert("NFT is already listed");
        marketplace.listNFT(tokenId, price, address(0));
        vm.stopPrank();
    }

    // ============ Purchase Tests ============
    function testBuyNFT() public {
        // Setup listing
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this)); // Using test contract as staking contract
        vm.stopPrank();

        // Execute purchase
        vm.expectEmit(true, true, true, true);
        emit NFTPurchased(tokenId, address(this));
        
        marketplace.buyNFT(tokenId);

        // Verify state changes
        assertEq(nftContract.ownerOf(tokenId), address(this), "NFT not transferred");
        assertEq(marketplace.earnings(tokenId), price, "Earnings not recorded");
        assertFalse(marketplace.listedBool(tokenId), "NFT should be unlisted after purchase");
        
        // Verify original price storage
        assertEq(marketplace.originalPrices(tokenId), price, "Original price not stored");
    }

    function testBuyNFTFailsIfNotListed() public {
        vm.expectRevert("NFT is not listed");
        marketplace.buyNFT(tokenId);
    }

    function testBuyNFTFailsIfWrongCaller() public {
        // Setup listing
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(0x123)); // Different staking contract
        vm.stopPrank();

        vm.expectRevert("Only assigned staking contract can buy");
        marketplace.buyNFT(tokenId);
    }

    // ============ Relisting Tests ============
    function testRelistNFT() public {
        // Setup initial listing
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        vm.stopPrank();

        // Relist with new price
        vm.startPrank(nftOwner);
        vm.expectEmit(true, true, true, true);
        emit NFTListed(tokenId, newPrice, nftOwner);
        
        marketplace.relistNFT(tokenId, newPrice);
        vm.stopPrank();

        // Verify listing updates
        (uint256 listedPrice,, bool isListed) = marketplace.listings(tokenId);
        assertEq(listedPrice, newPrice, "Price not updated");
        assertTrue(isListed, "NFT should remain listed");
        
        // Verify stablecoin burning and minting
        uint256 expectedBurned = (price * 135) / 100;
        uint256 expectedMinted = (newPrice * 115) / 100;
        assertEq(stablecoin.balanceOf(address(marketplace)), expectedMinted, "Stablecoin amounts incorrect");
    }

    function testRelistNFTFailsIfNotOwner() public {
        // Setup initial listing
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        vm.stopPrank();

        vm.startPrank(otherAccount);
        vm.expectRevert("Only NFT owner can resell");
        marketplace.relistNFT(tokenId, newPrice);
        vm.stopPrank();
    }

    // ============ Earnings Tests ============
    function testWithdrawEarnings() public {
        // Setup purchase
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        vm.stopPrank();

        marketplace.buyNFT(tokenId);

        // Test withdrawal
        uint256 initialBalance = nftOwner.balance;
        vm.startPrank(nftOwner);
        vm.expectEmit(true, true, true, true);
        emit EarningsWithdrawn(tokenId, price);
        
        marketplace.withdrawEarnings(tokenId);
        vm.stopPrank();

        assertEq(nftOwner.balance, initialBalance + price, "Earnings not transferred");
        assertEq(marketplace.earnings(tokenId), 0, "Earnings not zeroed out");
    }

    function testWithdrawEarningsFailsIfNotOwner() public {
        vm.startPrank(otherAccount);
        vm.expectRevert("Only owner can withdraw");
        marketplace.withdrawEarnings(tokenId);
        vm.stopPrank();
    }

    // ============ Admin Functions ============
    function testDeleteListing() public {
        // Setup listing
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        vm.stopPrank();

        // Test deletion
        vm.startPrank(nftOwner);
        vm.expectEmit(true, true, true, true);
        emit StablecoinBurned(tokenId, (price * 135) / 100);
        
        marketplace.deleteListing(tokenId);
        vm.stopPrank();

        (,, bool isListed) = marketplace.listings(tokenId);
        assertFalse(isListed, "NFT should be unlisted");
        assertFalse(marketplace.listedBool(tokenId), "Listed bool not updated");
    }

    function testDeleteListingFailsIfNotListed() public {
        vm.startPrank(nftOwner);
        vm.expectRevert("NFT is not listed");
        marketplace.deleteListing(tokenId);
        vm.stopPrank();
    }

    // ============ Edge Cases ============
    function testHighValueListing() public {
        uint256 veryHighPrice = type(uint256).max / 2; // Avoid overflow
        
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        
        // Should handle large numbers without reverting
        marketplace.listNFT(tokenId, veryHighPrice, address(this));
        vm.stopPrank();

        uint256 expectedStablecoins = (veryHighPrice * 135) / 100;
        assertEq(stablecoin.balanceOf(address(marketplace)), expectedStablecoins);
    }

    function testMultipleListingsAndPurchases() public {
        uint256 tokenId2 = 2;
        
        // Mint second NFT
        vm.startPrank(owner);
        nftContract.mint(nftOwner, tokenId2);
        vm.stopPrank();

        // List both NFTs
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        
        nftContract.approve(address(marketplace), tokenId2);
        marketplace.listNFT(tokenId2, price * 2, address(this));
        vm.stopPrank();

        // Purchase both
        marketplace.buyNFT(tokenId);
        marketplace.buyNFT(tokenId2);

        // Verify earnings
        assertEq(marketplace.earnings(tokenId), price);
        assertEq(marketplace.earnings(tokenId2), price * 2);
    }

    // ============ Original Price Tests ============
    function testOriginalPriceStorage() public {
        // Setup listing and purchase
        vm.startPrank(nftOwner);
        nftContract.approve(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, price, address(this));
        vm.stopPrank();

        marketplace.buyNFT(tokenId);

        // Verify original price
        assertEq(marketplace.getOriginalPrice(tokenId), price);
    }
}