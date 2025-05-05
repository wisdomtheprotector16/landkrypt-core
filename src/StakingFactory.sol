// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./NFTMarketplace.sol";
import "./NFTStaking.sol";
import "./RealEstateNFT.sol";
import "./LandKryptStakingToken.sol";
import "./DevelopmentContract.sol";
import "./LandKryptStablecoin.sol";

contract StakingFactory {
    NFTMarketplace public marketplace;
    LandKryptStablecoin public stablecoin;
    LandKryptStakingToken public stakingToken;
    RealEstateNFT public nftContract;
    DevelopmentContract public developmentContract;
    address public owner;
    
    // Track all deployed staking contracts and their associated NFTs
    address[] public stakingContracts;
    mapping(uint256 => address) public nftToStakingContract;
    mapping(address => uint256) public stakingContractToNFT;

    event StakingContractCreated(
        address indexed stakingContract, 
        uint256 indexed tokenId, 
        uint256 targetAmount,
        uint256 listingPrice
    );

    constructor(
        address _marketplace,
        address _stablecoin,
        address _stakingToken,
        address _realestatenft,
        address _developmentContract
    ) {
        marketplace = NFTMarketplace(_marketplace);
        stablecoin = LandKryptStablecoin(_stablecoin);
        stakingToken = LandKryptStakingToken(_stakingToken);
        nftContract = RealEstateNFT(_realestatenft);
        developmentContract = DevelopmentContract(_developmentContract);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    /**
     * @dev Deploys a new staking contract, lists NFT on marketplace, and sets up the staking pool
     * @param tokenId The NFT token ID to stake against
     * @param targetAmount The target staking amount to purchase the NFT
     * @param listingPrice The price to list the NFT for on the marketplace
     */
    function createStakingContract(
        uint256 tokenId,
        uint256 targetAmount,
        uint256 listingPrice
    ) external {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(nftToStakingContract[tokenId] == address(0), "Staking contract already exists for this NFT");

        // Deploy new staking contract
        NFTStaking stakingContract = new NFTStaking(
            address(marketplace),
            address(stablecoin),
            address(stakingToken),
            address(developmentContract),
            tokenId,
            targetAmount
        );

        // Store contract references
        address stakingAddress = address(stakingContract);
        stakingContracts.push(stakingAddress);
        nftToStakingContract[tokenId] = stakingAddress;
        stakingContractToNFT[stakingAddress] = tokenId;

        // Transfer NFT to marketplace for listing
        nftContract.transferFrom(msg.sender, address(marketplace), tokenId);

        // List NFT on marketplace with the staking contract as buyer
        marketplace.listNFT(tokenId, listingPrice, stakingAddress);

        emit StakingContractCreated(stakingAddress, tokenId, targetAmount, listingPrice);
    }

    /**
     * @dev Gets the staking contract address for a specific NFT
     * @param tokenId The NFT token ID
     * @return address The staking contract address
     */
    function getStakingContractForNFT(uint256 tokenId) external view returns (address) {
        return nftToStakingContract[tokenId];
    }

    /**
     * @dev Gets the NFT token ID for a specific staking contract
     * @param stakingContract The staking contract address
     * @return uint256 The NFT token ID
     */
    function getNFTForStakingContract(address stakingContract) external view returns (uint256) {
        return stakingContractToNFT[stakingContract];
    }

    /**
     * @dev Gets count of deployed staking contracts
     * @return uint256 The number of staking contracts
     */
    function getStakingContractsCount() external view returns (uint256) {
        return stakingContracts.length;
    }

    /**
     * @dev Gets paginated list of staking contracts
     * @param start The starting index
     * @param end The ending index
     * @return address[] Array of staking contract addresses
     */
    function getStakingContractsPaginated(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory) {
        require(start <= end && end < stakingContracts.length, "Invalid range");
        address[] memory result = new address[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            result[i - start] = stakingContracts[i];
        }
        return result;
    }

    /**
     * @dev Transfers ownership of the factory
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner address");
        owner = newOwner;
    }

    /**
     * @dev Emergency function to recover NFT if staking fails
     * @param tokenId The NFT token ID to recover
     */
    function recoverNFT(uint256 tokenId) external onlyOwner {
        require(nftToStakingContract[tokenId] != address(0), "No staking contract for this NFT");
        address stakingContract = nftToStakingContract[tokenId];
        
        // Only allow recovery if NFT hasn't been purchased yet
        NFTStaking staking = NFTStaking(stakingContract);
        require(staking.totalStaked() < staking.targetAmount(), "NFT already purchased");

        // Transfer NFT back to factory owner
        nftContract.transferFrom(address(marketplace), owner, tokenId);
        
        // Clean up mappings
        delete nftToStakingContract[tokenId];
        delete stakingContractToNFT[stakingContract];
    }
}