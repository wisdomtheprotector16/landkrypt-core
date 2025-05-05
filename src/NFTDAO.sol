// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@chainlink/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "./DevelopmentContract.sol";
import "./NFTStaking.sol";
import "./LandKryptStakingToken.sol";
import "./NFTMarketplace.sol";

/**
 * @title NFTDAO
 * @dev Governance contract for LandKrypt development proposals with NFT price-based quorum
 */
contract NFTDAO is Ownable, AutomationCompatibleInterface {
    struct Proposal {
        uint256 id;
        string description;
        uint256 voteEndTime;
        uint256 yesVotes;
        bool executed;
        address developer;
        uint256 ownershipPercentage;
        uint256 landNFTId;
        uint256 projectTimeframe;
    }

    LandKryptStakingToken public stakingToken; // LKST
    DevelopmentContract public developmentContract;
    NFTStaking public stakingContract;
    NFTMarketplace public nftMarketplace;
    uint256 public proposalCount;
    uint256 public votingPeriod; // Voting period in seconds
    uint256 public quorum; // Minimum percentage of NFT value required to pass a proposal
    uint256 public developerFee; // Fee for developers to register

    // Track all proposals per NFT
    mapping(uint256 => uint256[]) public nftProposals;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => uint256)) public votesByAddress;
    mapping(uint256 => uint256) public totalStakedAtProposal;
    mapping(address => bool) public registeredDevelopers;
    mapping(uint256 => uint256) public nftPurchaseTime;
    mapping(uint256 => uint256) public nftPurchasePrices; // Stores original NFT prices
    mapping(uint256 => uint256) public totalVotesForNFT;

    event ProposalCreated(uint256 id, string description, uint256 voteEndTime, address developer, uint256 ownershipPercentage, uint256 landNFTId);
    event Voted(uint256 proposalId, address voter, uint256 amount);
    event ProposalExecuted(uint256 id, address developer, uint256 ownershipPercentage, uint256 landNFTId);
    event DeveloperRegistered(address developer);
    event TokensBurned(uint256 landNFTId, uint256 amount);

    constructor(
        address _stakingToken,
        address _nftMarketplace,
        address _developmentContract,
        address _stakingContract,
        uint256 _votingPeriod,
        uint256 _quorum,
        uint256 _developerFee
    ) {
        stakingToken = LandKryptStakingToken(_stakingToken);
        developmentContract = DevelopmentContract(_developmentContract);
        stakingContract = NFTStaking(_stakingContract);
        nftMarketplace = NFTMarketplace(_nftMarketplace);
        votingPeriod = _votingPeriod;
        quorum = _quorum;
        developerFee = _developerFee;
    }

    /**
     * @dev Registers a developer by paying the required fee
     */
    function registerDeveloper() external payable {
        require(msg.value >= developerFee, "Insufficient fee");
        require(!registeredDevelopers[msg.sender], "Already registered");
        registeredDevelopers[msg.sender] = true;
        emit DeveloperRegistered(msg.sender);
    }

    /**
     * @dev Records NFT purchase time and price (called by marketplace)
     * @param landNFTId The ID of the purchased NFT
     * @param price The original purchase price of the NFT
     */
    function recordNFTPurchase(uint256 landNFTId, uint256 price) external {
        require(msg.sender == address(nftMarketplace), "Only marketplace can record");
        require(nftPurchaseTime[landNFTId] == 0, "Purchase already recorded");
        
        nftPurchaseTime[landNFTId] = block.timestamp;
        nftPurchasePrices[landNFTId] = price;
    }

    /**
     * @dev Creates a new development proposal
     */
    function createProposal(
        string memory description,
        address developer,
        uint256 ownershipPercentage,
        uint256 landNFTId,
        uint256 projectTimeframe
    ) external {
        require(registeredDevelopers[msg.sender], "Only registered developers can propose");
        require(stakingContract.totalStaked() >= stakingContract.targetAmount(), "LandNFT not fully staked");
        require(!developmentContract.hasDevelopmentContract(landNFTId), "Contract already exists");
        require(block.timestamp <= nftPurchaseTime[landNFTId] + votingPeriod, "Proposal period ended");
        require(ownershipPercentage <= 100, "Invalid ownership percentage");
        require(projectTimeframe > 0, "Invalid timeframe");

        proposalCount++;
        uint256 voteEndTime = block.timestamp + votingPeriod;
        totalStakedAtProposal[proposalCount] = stakingToken.totalSupply();

        proposals[proposalCount] = Proposal({
            id: proposalCount,
            description: description,
            voteEndTime: voteEndTime,
            yesVotes: 0,
            executed: false,
            developer: developer,
            ownershipPercentage: ownershipPercentage,
            landNFTId: landNFTId,
            projectTimeframe: projectTimeframe
        });

        nftProposals[landNFTId].push(proposalCount);
        emit ProposalCreated(proposalCount, description, voteEndTime, developer, ownershipPercentage, landNFTId);
    }

    /**
     * @dev Votes on a proposal using LKST tokens
     */
    function vote(uint256 proposalId, uint256 voteAmount) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.voteEndTime, "Voting period ended");
        require(voteAmount > 0, "Must vote positive amount");

        uint256 voterStake = stakingToken.balanceOf(msg.sender);
        require(voterStake >= voteAmount, "Insufficient staking tokens");
        require(votesByAddress[proposalId][msg.sender] == 0, "Already voted");

        stakingToken.transferFrom(msg.sender, address(this), voteAmount);
        
        proposal.yesVotes += voteAmount;
        votesByAddress[proposalId][msg.sender] = voteAmount;
        totalVotesForNFT[proposal.landNFTId] += voteAmount;

        emit Voted(proposalId, msg.sender, voteAmount);
    }

    /**
     * @dev Executes the winning proposal for a land NFT
     */
    function executeProposal(uint256 landNFTId) external {
        uint256[] memory proposalIds = nftProposals[landNFTId];
        require(proposalIds.length > 0, "No proposals for NFT");

        // Find winning proposal
        uint256 winningProposalId;
        uint256 maxVotes;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            Proposal storage proposal = proposals[proposalIds[i]];
            if (block.timestamp > proposal.voteEndTime && 
                !proposal.executed && 
                proposal.yesVotes > maxVotes) {
                maxVotes = proposal.yesVotes;
                winningProposalId = proposalIds[i];
            }
        }

        require(winningProposalId != 0, "No executable proposal");
        Proposal storage winningProposal = proposals[winningProposalId];

        // NEW QUORUM LOGIC: Votes must meet percentage of NFT's original price
        uint256 nftPrice = nftPurchasePrices[winningProposal.landNFTId];
        uint256 minRequiredVotes = (nftPrice * quorum) / 100;
        require(winningProposal.yesVotes >= minRequiredVotes, 
            "Insufficient votes relative to NFT value");

        // Create development contract
        developmentContract.mintDevelopmentContract(
            winningProposal.developer,
            winningProposal.landNFTId,
            winningProposal.ownershipPercentage,
            winningProposal.projectTimeframe
        );

        // Burn all votes for this NFT
        uint256 totalToBurn = totalVotesForNFT[landNFTId];
        stakingToken.burn(address(this), totalToBurn);
        emit TokensBurned(landNFTId, totalToBurn);

        winningProposal.executed = true;
        emit ProposalExecuted(winningProposalId, winningProposal.developer, 
            winningProposal.ownershipPercentage, winningProposal.landNFTId);
    }

    /**
     * @dev Chainlink Keeper check function
     */
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 1; i <= proposalCount; i++) {
            Proposal memory proposal = proposals[i];
            if (block.timestamp > proposal.voteEndTime &&
                !proposal.executed) {
                
                // Check against NFT price
                uint256 nftPrice = nftPurchasePrices[proposal.landNFTId];
                uint256 minRequiredVotes = (nftPrice * quorum) / 100;
                
                if (proposal.yesVotes >= minRequiredVotes) {
                    upkeepNeeded = true;
                    performData = abi.encode(proposal.landNFTId);
                    break;
                }
            }
        }
    }

    /**
     * @dev Chainlink Keeper perform function
     */
    function performUpkeep(bytes calldata performData) external override {
        uint256 landNFTId = abi.decode(performData, (uint256));
        executeProposal(landNFTId);
    }

    // Admin functions
    function updateVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        votingPeriod = newVotingPeriod;
    }

    function updateQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Invalid quorum");
        quorum = newQuorum;
    }

    function updateDeveloperFee(uint256 newFee) external onlyOwner {
        developerFee = newFee;
    }
}