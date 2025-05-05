// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/NFTDAO.sol";
import "../src/LandKryptStakingToken.sol";
import "../src/DevelopmentContract.sol";
import "../src/NFTStaking.sol";
import "../src/NFTMarketplace.sol";
import "../src/RealEstateNFT.sol";
import "../src/LandKryptStablecoin.sol";

contract NFTDAOTest is Test {
    NFTDAO public dao;
    LandKryptStakingToken public stakingToken;
    DevelopmentContract public devContract;
    NFTStaking public stakingContract;
    NFTMarketplace public marketplace;
    RealEstateNFT public nft;
    LandKryptStablecoin public stablecoin;
    
    address owner = address(0x1);
    address developer = address(0x2);
    address staker1 = address(0x3);
    address staker2 = address(0x4);
    
    uint256 tokenId = 1;
    uint256 targetAmount = 1000 ether;
    uint256 votingPeriod = 7 days;
    uint256 quorum = 30; // 30%
    uint256 developerFee = 0.1 ether;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy ecosystem contracts
        stablecoin = new LandKryptStablecoin();
        nft = new RealEstateNFT("https://ipfs.io/");
        marketplace = new NFTMarketplace(address(nft), address(stablecoin), address(this));
        stakingToken = new LandKryptStakingToken();
        devContract = new DevelopmentContract();
        
        // Deploy staking contract
        stakingContract = new NFTStaking(
            address(marketplace),
            address(stablecoin),
            address(stakingToken),
            address(devContract),
            tokenId,
            targetAmount
        );
        
        // Deploy DAO
        dao = new NFTDAO(
            address(stakingToken),
            address(marketplace),
            address(devContract),
            address(stakingContract),
            votingPeriod,
            quorum,
            developerFee
        );
        
        // Setup permissions
        stakingToken.transferOwnership(address(dao));
        nft.mint(owner, tokenId, "Test Property", "QmTestHash");
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(developer, 1 ether);
        vm.prank(owner);
        stakingToken.mint(staker1, 500 ether);
        vm.prank(owner);
        stakingToken.mint(staker2, 500 ether);
    }

    // ========== Developer Registration Tests ==========
    function test_RegisterDeveloper() public {
        vm.prank(developer);
        dao.registerDeveloper{value: developerFee}();
        
        assertTrue(dao.registeredDevelopers(developer));
    }

    function test_RegisterDeveloperFailsWithInsufficientFee() public {
        vm.prank(developer);
        vm.expectRevert("Insufficient fee");
        dao.registerDeveloper{value: developerFee - 0.01 ether}();
    }

    function test_RegisterDeveloperFailsIfAlreadyRegistered() public {
        vm.prank(developer);
        dao.registerDeveloper{value: developerFee}();
        
        vm.prank(developer);
        vm.expectRevert("Already registered");
        dao.registerDeveloper{value: developerFee}();
    }

    // ========== Proposal Creation Tests ==========
    function test_CreateProposal() public {
        // Setup
        vm.prank(developer);
        dao.registerDeveloper{value: developerFee}();
        
        // Simulate NFT purchase
        vm.prank(address(marketplace));
        dao.recordNFTPurchaseTime(tokenId);
        
        // Simulate staking target reached
        vm.prank(owner);
        stakingToken.mint(address(stakingContract), targetAmount);
        
        // Create proposal
        string memory description = "Build luxury condos";
        uint256 ownershipPercentage = 20;
        uint256 timeframe = 365 days;
        
        vm.prank(owner);
        dao.createProposal(description, developer, ownershipPercentage, tokenId, timeframe);
        
        // Verify proposal
        (uint256 id, , uint256 voteEndTime, uint256 yesVotes, uint256 noVotes, bool executed, address dev, uint256 perc, uint256 nftId) = dao.proposals(1);
        assertEq(id, 1);
        assertEq(voteEndTime, block.timestamp + votingPeriod);
        assertEq(yesVotes, 0);
        assertEq(noVotes, 0);
        assertFalse(executed);
        assertEq(dev, developer);
        assertEq(perc, ownershipPercentage);
        assertEq(nftId, tokenId);
    }

    function test_CreateProposalFailsIfNotOwner() public {
        vm.prank(developer);
        vm.expectRevert("Ownable: caller is not the owner");
        dao.createProposal("Test", developer, 20, tokenId, 365 days);
    }

    function test_CreateProposalFailsIfDeveloperNotRegistered() public {
        vm.prank(owner);
        vm.expectRevert("Developer not registered");
        dao.createProposal("Test", developer, 20, tokenId, 365 days);
    }

    function test_CreateProposalFailsIfNFTNotFullyStaked() public {
        vm.prank(developer);
        dao.registerDeveloper{value: developerFee}();
        
        vm.prank(owner);
        vm.expectRevert("LandNFT not fully sold to staking contract");
        dao.createProposal("Test", developer, 20, tokenId, 365 days);
    }

    // ========== Voting Tests ==========
    function test_VoteOnProposal() public {
        // Setup proposal
        setupProposal();
        
        // Vote
        uint256 voteAmount = 100 ether;
        vm.prank(staker1);
        stakingToken.approve(address(dao), voteAmount);
        
        vm.prank(staker1);
        dao.vote(1, true, voteAmount);
        
        // Verify vote
        (,, uint256 yesVotes, uint256 noVotes,,, , ,) = dao.proposals(1);
        assertEq(yesVotes, voteAmount);
        assertTrue(dao.hasVoted(1, staker1));
    }

    function test_VoteFailsAfterVotingPeriod() public {
        setupProposal();
        skip(votingPeriod + 1);
        
        vm.prank(staker1);
        stakingToken.approve(address(dao), 100 ether);
        
        vm.prank(staker1);
        vm.expectRevert("Voting period has ended");
        dao.vote(1, true, 100 ether);
    }

    function test_VoteFailsIfAlreadyVoted() public {
        setupProposal();
        
        vm.prank(staker1);
        stakingToken.approve(address(dao), 100 ether);
        vm.prank(staker1);
        dao.vote(1, true, 100 ether);
        
        vm.prank(staker1);
        vm.expectRevert("Already voted");
        dao.vote(1, true, 50 ether);
    }

    // ========== Proposal Execution Tests ==========
    function test_ExecuteProposal() public {
        // Setup and vote
        setupProposal();
        castVotes(1, 400 ether, 100 ether); // 400 yes, 100 no
        
        // Fast forward past voting period
        skip(votingPeriod + 1);
        
        // Execute
        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(1, developer, 20, tokenId);
        
        dao.executeProposal(tokenId);
        
        // Verify execution
        (,,,,, bool executed,,,) = dao.proposals(1);
        assertTrue(executed);
        
        // Verify dev contract creation
        assertTrue(devContract.hasDevelopmentContract(tokenId));
    }

    function test_ExecuteProposalFailsIfQuorumNotMet() public {
        setupProposal();
        castVotes(1, 200 ether, 50 ether); // 250 total < 30% of 1000
        
        skip(votingPeriod + 1);
        
        vm.expectRevert("Quorum not met");
        dao.executeProposal(tokenId);
    }

    function test_ExecuteProposalFailsIfInsufficientYesVotes() public {
        setupProposal();
        castVotes(1, 300 ether, 200 ether); // 300 yes < 333 (1/3 of 1000)
        
        skip(votingPeriod + 1);
        
        vm.expectRevert("Insufficient Yes votes");
        dao.executeProposal(tokenId);
    }

    // ========== Keeper Functions Tests ==========
    function test_CheckUpkeepReturnsTrueWhenReady() public {
        setupProposal();
        castVotes(1, 400 ether, 100 ether);
        skip(votingPeriod + 1);
        
        (bool upkeepNeeded, bytes memory performData) = dao.checkUpkeep("");
        assertTrue(upkeepNeeded);
        assertEq(abi.decode(performData, (uint256)), tokenId);
    }

    function test_PerformUpkeepExecutesProposal() public {
        setupProposal();
        castVotes(1, 400 ether, 100 ether);
        skip(votingPeriod + 1);
        
        vm.prank(address(0x123)); // Simulate keeper
        dao.performUpkeep(abi.encode(tokenId));
        
        (,,,,, bool executed,,,) = dao.proposals(1);
        assertTrue(executed);
    }

    // ========== Helper Functions ==========
    function setupProposal() internal {
        // Register developer
        vm.prank(developer);
        dao.registerDeveloper{value: developerFee}();
        
        // Record NFT purchase
        vm.prank(address(marketplace));
        dao.recordNFTPurchaseTime(tokenId);
        
        // Simulate staking target reached
        vm.prank(owner);
        stakingToken.mint(address(stakingContract), targetAmount);
        
        // Create proposal
        vm.prank(owner);
        dao.createProposal("Test", developer, 20, tokenId, 365 days);
    }

    function castVotes(uint256 proposalId, uint256 yesAmount, uint256 noAmount) internal {
        vm.prank(staker1);
        stakingToken.approve(address(dao), yesAmount);
        vm.prank(staker1);
        dao.vote(proposalId, true, yesAmount);
        
        vm.prank(staker2);
        stakingToken.approve(address(dao), noAmount);
        vm.prank(staker2);
        dao.vote(proposalId, false, noAmount);
    }

    // ========== Fuzz Tests ==========
    function testFuzz_Voting(uint256 yesAmount, uint256 noAmount) public {
        yesAmount = bound(yesAmount, 1 ether, 500 ether);
        noAmount = bound(noAmount, 1 ether, 500 ether);
        
        setupProposal();
        
        vm.prank(staker1);
        stakingToken.approve(address(dao), yesAmount);
        vm.prank(staker1);
        dao.vote(1, true, yesAmount);
        
        vm.prank(staker2);
        stakingToken.approve(address(dao), noAmount);
        vm.prank(staker2);
        dao.vote(1, false, noAmount);
        
        (,, uint256 yesVotes, uint256 noVotes,,, , ,) = dao.proposals(1);
        assertEq(yesVotes, yesAmount);
        assertEq(noVotes, noAmount);
    }
}