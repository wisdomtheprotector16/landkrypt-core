// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./DevelopmentContract.sol";
import "./NFTStaking.sol";
import "./LandKryptStakingToken.sol";
import "./NFTMarketplace.sol";


contract NFTDAO is Ownable, AutomationCompatibleInterface {
    struct Proposal {
        uint256 id;
        string description;
        uint256 voteEndTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        address developer;
        uint256 ownershipPercentage;
        uint256 landNFTId;
    }

    LandKryptStakingToken public stakingToken; // LKST
    DevelopmentContract public developmentContract;
    NFTStaking public stakingContract;
    uint256 public proposalCount;
    uint256 public votingPeriod; // Voting period in seconds (e.g., 7 days)
    uint256 public quorum; // Minimum percentage of total staked tokens required to pass a proposal
    uint256 public developerFee; // Fee for developers to register

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => uint256) public totalStakedAtProposal; // Total staked tokens at the time of proposal creation
    mapping(address => bool) public registeredDevelopers; // Tracks registered developers
    mapping(uint256 => uint256) public nftPurchaseTime; // Maps NFT ID to its purchase time
    mapping(uint256 => uint256[]) public nftProposals; // Maps NFT ID to its associated proposal IDs

    event ProposalCreated(uint256 id, string description, uint256 voteEndTime, address developer, uint256 ownershipPercentage, uint256 landNFTId);
    event Voted(uint256 proposalId, address voter, bool vote, uint256 weight);
    event ProposalExecuted(uint256 id, address developer, uint256 ownershipPercentage, uint256 landNFTId);
    event DeveloperRegistered(address developer);
    event TokensBurned(uint256 proposalId, uint256 amount);

    constructor(address _stakingToken, address _nftMarketplace, address _developmentContract, address _stakingContract, uint256 _votingPeriod, uint256 _quorum, uint256 _developerFee) {
        stakingToken = LandKryptStakingToken(_stakingToken);
        developmentContract = DevelopmentContract(_developmentContract);
        stakingContract = NFTStaking(_stakingContract);
        nftMarketplace = NFTMarketplace(_nftMarketplace);
        votingPeriod = _votingPeriod;
        quorum = _quorum;
        developerFee = _developerFee;
    }

    // Register as a developer
    function registerDeveloper() external payable {
        require(msg.value >= developerFee, "Insufficient fee");
        require(!registeredDevelopers[msg.sender], "Already registered");

        registeredDevelopers[msg.sender] = true;
        emit DeveloperRegistered(msg.sender);
    }

    // Record NFT purchase time
    function recordNFTPurchaseTime(uint256 landNFTId) external {
        require(msg.sender == address(nftMarketplace), "Only nftMarketplace can record purchase time");
        require(nftPurchaseTime[landNFTId] == 0, "Purchase time already recorded");
        nftPurchaseTime[landNFTId] = block.timestamp;
    }

    // Create a new proposal for a development contract
    


    // Modified createProposal function to include timeframe
    function createProposal(
        string memory description, 
        address developer, 
        uint256 ownershipPercentage, 
        uint256 landNFTId,
        uint256 projectTimeframe // Added parameter
    ) external onlyOwner {
        require(registeredDevelopers[developer], "Developer not registered");
        require(stakingContract.totalStaked() >= stakingContract.targetAmount(), "LandNFT not fully sold to staking contract");
        require(!developmentContract.hasDevelopmentContract(landNFTId), "Development Contract already exists for this LandNFT");
        require(block.timestamp <= nftPurchaseTime[landNFTId] + votingPeriod, "Proposal creation period has ended");
        require(projectTimeframe > 0, "Timeframe must be positive");

        proposalCount++;
        uint256 voteEndTime = block.timestamp + votingPeriod;
        totalStakedAtProposal[proposalCount] = stakingToken.totalSupply();

        proposals[proposalCount] = Proposal({
            id: proposalCount,
            description: description,
            voteEndTime: voteEndTime,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            developer: developer,
            ownershipPercentage: ownershipPercentage,
            landNFTId: landNFTId,
            projectTimeframe: projectTimeframe // Added
        });
         nftProposals[landNFTId].push(proposalCount);
        emit ProposalCreated(proposalCount, description, voteEndTime, developer, ownershipPercentage, landNFTId);
    }


    // Vote on a proposal using LKST
    function vote(uint256 proposalId, bool voteYes, uint256 voteAmount) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.voteEndTime, "Voting period has ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        uint256 voterStake = stakingToken.balanceOf(msg.sender);
        require(voterStake >= voteAmount, "Insufficient staking tokens");

        // Transfer LKST from voter to this contract
        stakingToken.transferFrom(msg.sender, address(this), voteAmount);

        if (voteYes) {
            proposal.yesVotes += voteAmount;
        } else {
            proposal.noVotes += voteAmount;
        }

        hasVoted[proposalId][msg.sender] = true;
        emit Voted(proposalId, msg.sender, voteYes, voteAmount);
    }

    // Execute the proposal with the highest votes for a specific NFT
    function executeProposal(uint256 landNFTId) external {
        uint256[] memory proposalIds = nftProposals[landNFTId];
        require(proposalIds.length > 0, "No proposals for this NFT");

        uint256 winningProposalId;
        uint256 maxVotes;

        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage proposal = proposals[proposalIds[i]];
            if (block.timestamp > proposal.voteEndTime && !proposal.executed && proposal.yesVotes > maxVotes) {
                maxVotes = proposal.yesVotes;
                winningProposalId = proposalIds[i];
            }
        }

        require(winningProposalId != 0, "No executable proposal found");

        Proposal storage winningProposal = proposals[winningProposalId];
        require(winningProposal.yesVotes > (stakingContract.targetAmount() / 3), "Insufficient Yes votes");
        require(winningProposal.yesVotes + winningProposal.noVotes >= (totalStakedAtProposal[winningProposalId] * quorum) / 100, "Quorum not met");

        // Mint a Development Contract NFT
        developmentContract.mintDevelopmentContract(
            winningProposal.developer,
            winningProposal.landNFTId,
            winningProposal.ownershipPercentage,
            winningProposal.projectTimeframe // Added
        );

        // Burn the LKST tokens used for voting
        uint256 totalVotes = winningProposal.yesVotes + winningProposal.noVotes;
        stakingToken.burn(address(this), totalVotes);
        emit TokensBurned(winningProposalId, totalVotes);

        winningProposal.executed = true;
        emit ProposalExecuted(winningProposalId, winningProposal.developer, winningProposal.ownershipPercentage, winningProposal.landNFTId);
    }

    // Chainlink Keeper function to check if a proposal can be executed
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 1; i <= proposalCount; i++) {
            Proposal memory proposal = proposals[i];
            if (
                block.timestamp > proposal.voteEndTime &&
                !proposal.executed &&
                proposal.yesVotes > (stakingContract.targetAmount() / 3) &&
                proposal.yesVotes + proposal.noVotes >= (totalStakedAtProposal[i] * quorum) / 100
            ) {
                upkeepNeeded = true;
                performData = abi.encode(proposal.landNFTId);
                break;
            }
        }
    }

    // Chainlink Keeper function to execute a proposal
    function performUpkeep(bytes calldata performData) external override {
        uint256 landNFTId = abi.decode(performData, (uint256));
        executeProposal(landNFTId);
    }

    // Update voting period (only owner)
    function updateVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        votingPeriod = newVotingPeriod;
    }

    // Update quorum (only owner)
    function updateQuorum(uint256 newQuorum) external onlyOwner {
        quorum = newQuorum;
    }

    // Update developer fee (only owner)
    function updateDeveloperFee(uint256 newFee) external onlyOwner {
        developerFee = newFee;
    }
}