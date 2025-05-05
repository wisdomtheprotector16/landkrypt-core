// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/StakingFactory.sol";
import "../contracts/NFTMarketplace.sol";
import "../contracts/RealEstateNFT.sol";
import "../contracts/LandKryptStakingToken.sol";
import "../contracts/DevelopmentContract.sol";
import "../contracts/LandKryptStablecoin.sol";
import "../contracts/NFTStaking.sol";

contract StakingFactoryTest is Test {
    StakingFactory public factory;
    NFTMarketplace public marketplace;
    RealEstateNFT public nftContract;
    LandKryptStakingToken public stakingToken;
    DevelopmentContract public developmentContract;
    LandKryptStablecoin public stablecoin;
    
    address owner = address(0x1);
    address nftOwner = address(0x2);
    address otherAccount = address(0x3);
    
    uint256 tokenId = 1;
    uint256 targetAmount = 1000 ether;
    uint256 listingPrice = 1000 ether;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy dependencies
        stablecoin = new LandKryptStablecoin();
        stakingToken = new LandKryptStakingToken();
        marketplace = new NFTMarketplace();
        nftContract = new RealEstateNFT();
        developmentContract = new DevelopmentContract();
        
        // Deploy factory
        factory = new StakingFactory(
            address(marketplace),
            address(stablecoin),
            address(stakingToken),
            address(nftContract),
            address(developmentContract)
        );
        
        // Mint NFT to test owner
        nftContract.mint(nftOwner, tokenId);
        vm.stopPrank();
    }

    // Deployment Tests
    function testDeployment() public {
        assertEq(factory.owner(), owner);
        assertEq(address(factory.marketplace()), address(marketplace));
        assertEq(address(factory.stablecoin()), address(stablecoin));
        assertEq(address(factory.stakingToken()), address(stakingToken));
        assertEq(address(factory.nftContract()), address(nftContract));
        assertEq(address(factory.developmentContract()), address(developmentContract));
        assertEq(factory.getStakingContractsCount(), 0);
    }

    // createStakingContract Tests
    function testCreateStakingContract() public {
        vm.startPrank(nftOwner);
        
        // Approve factory to transfer NFT (needed for listNFT)
        nftContract.approve(address(factory), tokenId);
        
        vm.expectEmit(true, true, true, true);
        emit StakingContractCreated(address(0), tokenId, targetAmount, listingPrice);
        
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        // Verify state changes
        address stakingAddress = factory.nftToStakingContract(tokenId);
        assertTrue(stakingAddress != address(0));
        
        assertEq(factory.stakingContracts(0), stakingAddress);
        assertEq(factory.stakingContractToNFT(stakingAddress), tokenId);
        assertEq(factory.getStakingContractsCount(), 1);
        
        // Verify NFT was transferred and listed
        assertEq(nftContract.ownerOf(tokenId), address(marketplace));
        
        // Verify staking contract was properly initialized
        NFTStaking staking = NFTStaking(stakingAddress);
        assertEq(address(staking.marketplace()), address(marketplace));
        assertEq(staking.tokenId(), tokenId);
        assertEq(staking.targetAmount(), targetAmount);
    }

    function testCreateStakingContractFailsIfNotNFTOwner() public {
        vm.startPrank(otherAccount);
        vm.expectRevert("Not NFT owner");
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
    }

    function testCreateStakingContractFailsIfContractExists() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        
        vm.expectRevert("Staking contract already exists for this NFT");
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
    }

    // View Function Tests
    function testGetStakingContractForNFT() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        address stakingAddress = factory.getStakingContractForNFT(tokenId);
        assertTrue(stakingAddress != address(0));
    }

    function testGetNFTForStakingContract() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        address stakingAddress = factory.nftToStakingContract(tokenId);
        uint256 fetchedTokenId = factory.getNFTForStakingContract(stakingAddress);
        assertEq(fetchedTokenId, tokenId);
    }

    function testGetStakingContractsPaginated() public {
        // Create multiple staking contracts
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;
            vm.startPrank(owner);
            nftContract.mint(nftOwner, tokenIds[i]);
            vm.stopPrank();
            
            vm.startPrank(nftOwner);
            nftContract.approve(address(factory), tokenIds[i]);
            factory.createStakingContract(tokenIds[i], targetAmount + i, listingPrice + i);
            vm.stopPrank();
        }
        
        // Test pagination
        address[] memory contracts = factory.getStakingContractsPaginated(1, 2);
        assertEq(contracts.length, 2);
        assertEq(contracts[0], factory.stakingContracts(1));
        assertEq(contracts[1], factory.stakingContracts(2));
    }

    // Ownership Tests
    function testTransferOwnership() public {
        vm.startPrank(owner);
        factory.transferOwnership(otherAccount);
        vm.stopPrank();
        
        assertEq(factory.owner(), otherAccount);
    }

    function testTransferOwnershipFailsIfNotOwner() public {
        vm.startPrank(nftOwner);
        vm.expectRevert("Only owner can call this function");
        factory.transferOwnership(otherAccount);
        vm.stopPrank();
    }

    function testTransferOwnershipFailsIfZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid owner address");
        factory.transferOwnership(address(0));
        vm.stopPrank();
    }

    // Emergency Recovery Tests
    function testRecoverNFT() public {
        // Setup staking contract
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        address stakingAddress = factory.nftToStakingContract(tokenId);
        
        // Verify NFT is with marketplace
        assertEq(nftContract.ownerOf(tokenId), address(marketplace));
        
        // Recover NFT
        vm.startPrank(owner);
        factory.recoverNFT(tokenId);
        vm.stopPrank();
        
        // Verify NFT was recovered
        assertEq(nftContract.ownerOf(tokenId), owner);
        
        // Verify mappings were cleaned up
        assertEq(factory.nftToStakingContract(tokenId), address(0));
        assertEq(factory.stakingContractToNFT(stakingAddress), 0);
    }

    function testRecoverNFTFailsIfNotOwner() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        vm.startPrank(otherAccount);
        vm.expectRevert("Only owner can call this function");
        factory.recoverNFT(tokenId);
        vm.stopPrank();
    }

    function testRecoverNFTFailsIfNFTAlreadyPurchased() public {
        // Setup staking contract
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        factory.createStakingContract(tokenId, targetAmount, listingPrice);
        vm.stopPrank();
        
        address stakingAddress = factory.nftToStakingContract(tokenId);
        
        // Simulate NFT purchase
        vm.startPrank(owner);
        stablecoin.mint(address(this), targetAmount);
        stablecoin.approve(stakingAddress, targetAmount);
        NFTStaking(stakingAddress).stake(targetAmount);
        vm.stopPrank();
        
        // Attempt recovery
        vm.startPrank(owner);
        vm.expectRevert("NFT already purchased");
        factory.recoverNFT(tokenId);
        vm.stopPrank();
    }

    // Edge Cases
    function testMultipleStakingContracts() public {
        uint256 count = 5;
        
        for (uint256 i = 1; i <= count; i++) {
            uint256 newTokenId = i + 100; // Different token IDs
            
            vm.startPrank(owner);
            nftContract.mint(nftOwner, newTokenId);
            vm.stopPrank();
            
            vm.startPrank(nftOwner);
            nftContract.approve(address(factory), newTokenId);
            factory.createStakingContract(newTokenId, targetAmount + i, listingPrice + i);
            vm.stopPrank();
            
            assertEq(factory.getStakingContractForNFT(newTokenId), factory.stakingContracts(i - 1));
        }
        
        assertEq(factory.getStakingContractsCount(), count);
    }

    function testZeroTargetAmount() public {
        vm.startPrank(nftOwner);
        nftContract.approve(address(factory), tokenId);
        
        // Should allow zero target amount (though likely not practical)
        factory.createStakingContract(tokenId, 0, listingPrice);
        vm.stopPrank();
        
        address stakingAddress = factory.nftToStakingContract(tokenId);
        assertTrue(stakingAddress != address(0));
    }
}