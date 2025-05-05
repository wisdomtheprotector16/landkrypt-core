// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./NFTMarketplace.sol";
import "./LandKryptStablecoin.sol";
import "./LandKryptStakingToken.sol";
import "./DevelopmentContract.sol";
import "@chainlink/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";
import "./RealEstateNFT.sol";


contract NFTStaking is AutomationCompatibleInterface, ReentrancyGuard {
    RealEstateNFT public nftContract;
    NFTMarketplace public marketplace;
    LandKryptStablecoin public stablecoin;
    LandKryptStakingToken public stakingToken; // LKST
    DevelopmentContract public developmentContract;
    uint256 public tokenId;
    uint256 public targetAmount;
    uint256 public totalStaked;
    address public owner;
    address public admin; // Land Krypt admin address
    

   

    // Daily reward rate (0.05% = 0.0005 in decimal)
    uint256 public constant DAILY_REWARD_RATE = 5e14; // 0.0005 (0.05%)
    uint256 public constant FINAL_REWARD_RATE = 110; // 110% (1.1x)

    // Staker information
    struct StakerInfo {
        uint256 amount;
        uint256 lastClaimDay;
        uint256 accumulatedRewards;
        uint256 finalRewardEligibleAmount;
    }

    // Contract state
    uint256 public contractCreationDay;
    mapping(address => StakerInfo) public stakers;
    mapping(uint256 => bool) public finalRewardDistributed;

    // Withdrawal penalty
    uint256 public withdrawalPenaltyRate; // Penalty rate for early withdrawals (e.g., 10 = 10%)
    bool public isWithdrawalPenaltyEnabled; // Toggle for enabling/disabling penalty

    event StakeAdded(address indexed staker, uint256 amount);
    event NFTPurchased(uint256 tokenId);
    event DailyRewardsClaimed(address indexed staker, uint256 amount);
    event FinalRewardsDistributed(address indexed staker, uint256 amount);
    event StakeWithdrawn(address indexed staker, uint256 amount, uint256 penalty);
    event WithdrawalPenaltyUpdated(uint256 newPenaltyRate);
    event AdminUpdated(address indexed newAdmin);
    event NFTTransferred(uint256 indexed tokenId, address indexed to);


    constructor(
        address _marketplace,
        address _stablecoin,
        address _stakingToken,
        address _developmentContract,
        uint256 _tokenId,
        uint256 _targetAmount
        address _nftContract, // Added NFT contrac
        address _admin // Added initial admin address
    ) {
        marketplace = NFTMarketplace(_marketplace);
        stablecoin = LandKryptStablecoin(_stablecoin);
        stakingToken = LandKryptStakingToken(_stakingToken);
        developmentContract = DevelopmentContract(_developmentContract);
        tokenId = _tokenId;
        targetAmount = _targetAmount;
        owner = msg.sender;
        contractCreationDay = block.timestamp / 1 days;
        withdrawalPenaltyRate = 10; // Default penalty rate (10%)
        isWithdrawalPenaltyEnabled = true; // Enable penalty by default
        nftContract = RealEstateNFT(_nftContract);
        admin = _admin;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only Land Krypt admin can call");
        _;
    }

    // Stake LKUSD towards buying the NFT
    function stake(uint256 amount) external nonReentrant {
        require(totalStaked + amount <= targetAmount, "Staking goal exceeded");
        require(amount > 0, "Must stake more than 0");

        // Transfer LKUSD from staker to this contract
        stablecoin.transferFrom(msg.sender, address(this), amount);

        // Initialize or update staker info
        StakerInfo storage staker = stakers[msg.sender];
        if (staker.lastClaimDay == 0) {
            staker.lastClaimDay = block.timestamp / 1 days;
        }

        // Update staking amounts
        staker.amount += amount;
        staker.finalRewardEligibleAmount += amount;
        totalStaked += amount;

        // Mint LKST to the staker
        stakingToken.mint(msg.sender, amount);

        emit StakeAdded(msg.sender, amount);

        if (totalStaked >= targetAmount) {
            purchaseNFT();
        }
    }

    // Internal function to purchase the NFT
    function purchaseNFT() internal {
        marketplace.buyNFT(tokenId);
        emit NFTPurchased(tokenId);
    }

    // Calculate and claim daily rewards
    function claimDailyRewards() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.amount > 0, "No active stake");

        uint256 currentDay = block.timestamp / 1 days;
        uint256 daysPassed = currentDay - staker.lastClaimDay;

        if (daysPassed > 0) {
            uint256 reward = (staker.amount * DAILY_REWARD_RATE * daysPassed) / 1e18;
            staker.accumulatedRewards += reward;
            staker.lastClaimDay = currentDay;

            if (reward > 0) {
                stablecoin.transfer(msg.sender, reward);
                emit DailyRewardsClaimed(msg.sender, reward);
            }
        }
    }

    // Distribute final rewards when project is completed
    function distributeFinalRewards() external nonReentrant {
        require(totalStaked >= targetAmount, "NFT not purchased yet");
        require(!finalRewardDistributed[tokenId], "Final rewards already distributed");

        uint256 deadline = developmentContract.getProjectDeadline(tokenId);
        require(block.timestamp > deadline, "Project not completed yet");

        finalRewardDistributed[tokenId] = true;

        // Distribute to all stakers
        // Note: In a production environment, you might want to implement a more gas-efficient distribution mechanism
        // for large numbers of stakers, possibly using merkle trees or other optimization techniques
        for (address stakerAddress in stakers) {
            StakerInfo storage staker = stakers[stakerAddress];
            if (staker.finalRewardEligibleAmount > 0) {
                uint256 finalReward = (staker.finalRewardEligibleAmount * FINAL_REWARD_RATE) / 100;
                staker.accumulatedRewards += finalReward;
                stablecoin.transfer(stakerAddress, finalReward);
                emit FinalRewardsDistributed(stakerAddress, finalReward);
            }
        }
    }

    // Allow stakers to withdraw their stake with a penalty
    function withdrawStake() external nonReentrant {
        require(totalStaked < targetAmount, "Staking goal already met");
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.amount > 0, "No stake to withdraw");

        // Claim any pending daily rewards first
        claimDailyRewards();

        uint256 penalty = 0;
        if (isWithdrawalPenaltyEnabled) {
            penalty = (staker.amount * withdrawalPenaltyRate) / 100;
        }

        uint256 amount = staker.amount - penalty;
        
        totalStaked -= staker.amount;
        staker.amount = 0;
        staker.finalRewardEligibleAmount = 0;

        // Transfer LKUSD back to staker
        stablecoin.transfer(msg.sender, amount);
        emit StakeWithdrawn(msg.sender, amount, penalty);
    }

    // Owner can update the withdrawal penalty rate
    function setWithdrawalPenaltyRate(uint256 newPenaltyRate) external onlyOwner {
        require(newPenaltyRate <= 100, "Penalty rate cannot exceed 100%");
        withdrawalPenaltyRate = newPenaltyRate;
        emit WithdrawalPenaltyUpdated(newPenaltyRate);
    }

    // Owner can enable/disable the withdrawal penalty
    function toggleWithdrawalPenalty(bool enabled) external onlyOwner {
        isWithdrawalPenaltyEnabled = enabled;
    }

    // Chainlink Keeper functions
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory) {
        if (totalStaked >= targetAmount && !finalRewardDistributed[tokenId]) {
            uint256 deadline = developmentContract.getProjectDeadline(tokenId);
            upkeepNeeded = block.timestamp > deadline;
        }
    }

    function performUpkeep(bytes calldata) external override {
        if (totalStaked >= targetAmount && !finalRewardDistributed[tokenId]) {
            uint256 deadline = developmentContract.getProjectDeadline(tokenId);
            if (block.timestamp > deadline) {
                distributeFinalRewards();
            }
        }
    }

    // View function to calculate pending daily rewards
    function calculatePendingDailyRewards(address stakerAddress) public view returns (uint256) {
        StakerInfo storage staker = stakers[stakerAddress];
        if (staker.amount == 0) return 0;

        uint256 currentDay = block.timestamp / 1 days;
        uint256 daysPassed = currentDay - staker.lastClaimDay;
        return (staker.amount * DAILY_REWARD_RATE * daysPassed) / 1e18;
    }

    // View function to get total claimable rewards (daily + final if eligible)
    function getTotalClaimableRewards(address stakerAddress) public view returns (uint256) {
        StakerInfo storage staker = stakers[stakerAddress];
        uint256 total = staker.accumulatedRewards + calculatePendingDailyRewards(stakerAddress);

        if (totalStaked >= targetAmount && !finalRewardDistributed[tokenId]) {
            uint256 deadline = developmentContract.getProjectDeadline(tokenId);
            if (block.timestamp > deadline) {
                total += (staker.finalRewardEligibleAmount * FINAL_REWARD_RATE) / 100;
            }
        }

        return total;
    }

     /**
     * @dev Transfer NFT to another address (admin only)
     * @param _tokenId ID of the NFT to transfer
     * @param _to Address to receive the NFT
     */
    function transferNFT(uint256 _tokenId, address _to) external onlyAdmin nonReentrant {
        require(_to != address(0), "Cannot transfer to zero address");
        require(nftContract.ownerOf(_tokenId) == address(this), "Contract doesn't own this NFT");
        
        nftContract.safeTransferFrom(address(this), _to, _tokenId);
        emit NFTTransferred(_tokenId, _to);
    }

    /**
     * @dev Update the admin address (owner only)
     * @param _newAdmin Address of the new admin
     */
    function updateAdmin(address _newAdmin) external onlyOwner {
        require(_newAdmin != address(0), "Invalid admin address");
        admin = _newAdmin;
        emit AdminUpdated(_newAdmin);
    }

}