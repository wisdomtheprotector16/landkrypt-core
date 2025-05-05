// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/NFTStaking.sol";
import "../contracts/NFTMarketplace.sol";
import "../contracts/LandKryptStablecoin.sol";
import "../contracts/LandKryptStakingToken.sol";
import "../contracts/DevelopmentContract.sol";
import "../contracts/RealEstateNFT.sol";

contract NFTStakingTest is Test {
    NFTStaking public staking;
    NFTMarketplace public marketplace;
    LandKryptStablecoin public stablecoin;
    LandKryptStakingToken public stakingToken;
    DevelopmentContract public devContract;
    RealEstateNFT public nftContract;
    
    address owner = address(0x1);
    address admin = address(0x2);
    address staker1 = address(0x3);
    address staker2 = address(0x4);
    
    uint256 tokenId = 1;
    uint256 targetAmount = 1000 ether;
    uint256 stakeAmount1 = 500 ether;
    uint256 stakeAmount2 = 500 ether;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock contracts
        stablecoin = new LandKryptStablecoin();
        stakingToken = new LandKryptStakingToken();
        marketplace = new NFTMarketplace();
        devContract = new DevelopmentContract();
        nftContract = new RealEstateNFT();
        
        // Deploy staking contract
        staking = new NFTStaking(
            address(marketplace),
            address(stablecoin),
            address(stakingToken),
            address(devContract),
            tokenId,
            targetAmount,
            address(nftContract),
            admin
        );
        
        // Setup initial state
        stablecoin.mint(staker1, stakeAmount1);
        stablecoin.mint(staker2, stakeAmount2);
        
        // Approve staking contract to spend stablecoins
        vm.stopPrank();
        vm.startPrank(staker1);
        stablecoin.approve(address(staking), stakeAmount1);
        vm.stopPrank();
        vm.startPrank(staker2);
        stablecoin.approve(address(staking), stakeAmount2);
        vm.stopPrank();
        
        // Mint NFT to marketplace
        vm.startPrank(owner);
        nftContract.mint(address(marketplace), tokenId);
        marketplace.listNFT(tokenId, targetAmount);
        vm.stopPrank();
    }

    // Deployment Tests
    function testDeployment() public {
        assertEq(staking.owner(), owner);
        assertEq(address(staking.marketplace()), address(marketplace));
        assertEq(address(staking.stablecoin()), address(stablecoin));
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(address(staking.developmentContract()), address(devContract));
        assertEq(staking.tokenId(), tokenId);
        assertEq(staking.targetAmount(), targetAmount);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.withdrawalPenaltyRate(), 10);
        assertTrue(staking.isWithdrawalPenaltyEnabled());
    }

    // Staking Functionality
    function testStake() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        assertEq(staking.totalStaked(), stakeAmount1);
        assertEq(staking.stakers(staker1).amount, stakeAmount1);
        assertEq(stakingToken.balanceOf(staker1), stakeAmount1);
        assertEq(stablecoin.balanceOf(address(staking)), stakeAmount1);
    }

    function testStakeFailsIfAmountZero() public {
        vm.startPrank(staker1);
        vm.expectRevert("Must stake more than 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function testStakeFailsIfExceedsTarget() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        vm.expectRevert("Staking goal exceeded");
        staking.stake(stakeAmount2 + 1);
        vm.stopPrank();
    }

    function testStakePurchasesNFTWhenTargetReached() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        staking.stake(stakeAmount2);
        vm.stopPrank();

        assertEq(staking.totalStaked(), targetAmount);
        assertEq(nftContract.ownerOf(tokenId), address(staking));
    }

    // Reward Calculation
    function testDailyRewardsCalculation() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        uint256 expectedReward = (stakeAmount1 * staking.DAILY_REWARD_RATE()) / 1e18;
        assertEq(staking.calculatePendingDailyRewards(staker1), expectedReward);
    }

    function testClaimDailyRewards() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        uint256 expectedReward = (stakeAmount1 * staking.DAILY_REWARD_RATE()) / 1e18;
        uint256 initialBalance = stablecoin.balanceOf(staker1);
        
        vm.startPrank(staker1);
        staking.claimDailyRewards();
        vm.stopPrank();

        assertEq(stablecoin.balanceOf(staker1), initialBalance + expectedReward);
        assertEq(staking.stakers(staker1).accumulatedRewards, expectedReward);
    }

    // Final Rewards
    function testFinalRewardsDistribution() public {
        // Setup complete stake
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();
        vm.startPrank(staker2);
        staking.stake(stakeAmount2);
        vm.stopPrank();

        // Setup development contract
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            address(0x5), // developer
            tokenId,
            30, // ownership percentage
            7 days // timeframe
        );
        vm.stopPrank();

        // Fast forward past deadline
        uint256 deadline = devContract.getProjectDeadline(tokenId);
        vm.warp(deadline + 1);

        // Distribute final rewards
        staking.distributeFinalRewards();

        uint256 expectedFinalReward1 = (stakeAmount1 * staking.FINAL_REWARD_RATE()) / 100;
        uint256 expectedFinalReward2 = (stakeAmount2 * staking.FINAL_REWARD_RATE()) / 100;

        assertEq(staking.stakers(staker1).accumulatedRewards, expectedFinalReward1);
        assertEq(staking.stakers(staker2).accumulatedRewards, expectedFinalReward2);
        assertTrue(staking.finalRewardDistributed(tokenId));
    }

    // Withdrawal Tests
    function testWithdrawStakeWithPenalty() public {
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        uint256 initialBalance = stablecoin.balanceOf(staker1);
        uint256 penalty = (stakeAmount1 * staking.withdrawalPenaltyRate()) / 100;
        uint256 expectedWithdrawal = stakeAmount1 - penalty;

        vm.startPrank(staker1);
        staking.withdrawStake();
        vm.stopPrank();

        assertEq(stablecoin.balanceOf(staker1), initialBalance + expectedWithdrawal);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.stakers(staker1).amount, 0);
    }

    function testWithdrawStakeWithoutPenalty() public {
        vm.startPrank(owner);
        staking.toggleWithdrawalPenalty(false);
        vm.stopPrank();

        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();

        uint256 initialBalance = stablecoin.balanceOf(staker1);

        vm.startPrank(staker1);
        staking.withdrawStake();
        vm.stopPrank();

        assertEq(stablecoin.balanceOf(staker1), initialBalance + stakeAmount1);
    }

    // Admin Functions
    function testTransferNFT() public {
        // First stake to purchase NFT
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();
        vm.startPrank(staker2);
        staking.stake(stakeAmount2);
        vm.stopPrank();

        // Test transfer
        vm.startPrank(admin);
        staking.transferNFT(tokenId, owner);
        vm.stopPrank();

        assertEq(nftContract.ownerOf(tokenId), owner);
    }

    function testTransferNFTFailsIfNotAdmin() public {
        vm.expectRevert("Only Land Krypt admin can call");
        staking.transferNFT(tokenId, owner);
    }

    // Chainlink Keeper
    function testCheckUpkeep() public {
        // First stake to purchase NFT
        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        vm.stopPrank();
        vm.startPrank(staker2);
        staking.stake(stakeAmount2);
        vm.stopPrank();

        // Setup development contract
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            address(0x5), // developer
            tokenId,
            30, // ownership percentage
            7 days // timeframe
        );
        vm.stopPrank();

        // Before deadline
        (bool upkeepNeededBefore,) = staking.checkUpkeep("");
        assertFalse(upkeepNeededBefore);

        // After deadline
        uint256 deadline = devContract.getProjectDeadline(tokenId);
        vm.warp(deadline + 1);
        (bool upkeepNeededAfter,) = staking.checkUpkeep("");
        assertTrue(upkeepNeededAfter);
    }

    // Edge Cases
    function testMultipleSmallStakes() public {
        uint256 smallAmount = 1 ether;
        uint256 iterations = 10;
        
        vm.startPrank(staker1);
        stablecoin.approve(address(staking), smallAmount * iterations);
        
        for (uint256 i = 0; i < iterations; i++) {
            staking.stake(smallAmount);
        }
        vm.stopPrank();

        assertEq(staking.totalStaked(), smallAmount * iterations);
        assertEq(staking.stakers(staker1).amount, smallAmount * iterations);
    }

    function testMaxPenaltyRate() public {
        vm.startPrank(owner);
        staking.setWithdrawalPenaltyRate(100); // 100% penalty
        vm.stopPrank();

        vm.startPrank(staker1);
        staking.stake(stakeAmount1);
        
        // Should receive nothing back
        uint256 initialBalance = stablecoin.balanceOf(staker1);
        staking.withdrawStake();
        assertEq(stablecoin.balanceOf(staker1), initialBalance);
        vm.stopPrank();
    }
}