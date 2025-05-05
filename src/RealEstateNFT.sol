// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC721/ERC721.sol";
import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/utils/Strings.sol";

contract RealEstateNFT is ERC721, Ownable {
    using Strings for uint256;

    // Struct to store token metadata
    struct TokenMetadata {
        string description; // Description of the land
        string ipfsHash; // IPFS hash of the metadata JSON file
    }

    // Mapping from token ID to its metadata
    mapping(uint256 => TokenMetadata) private _tokenMetadata;

    // Base URI for token metadata (e.g., "https://gateway.pinata.cloud/ipfs/")
    string private _baseTokenURI;

    constructor(string memory baseTokenURI) ERC721("RealEstateNFT", "LAND") {
        _baseTokenURI = baseTokenURI;
    }

    // Mint a new NFT with description and IPFS hash
    function mint(address to, uint256 tokenId, string memory description, string memory ipfsHash) external onlyOwner {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(bytes(ipfsHash).length > 0, "IPFS hash cannot be empty");

        _mint(to, tokenId);

        // Store token metadata
        _tokenMetadata[tokenId] = TokenMetadata({
            description: description,
            ipfsHash: ipfsHash
        });
    }

    // Get the token URI for a specific token ID
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        // Construct the full URI using the base URI and IPFS hash
        return string(abi.encodePacked(_baseTokenURI, _tokenMetadata[tokenId].ipfsHash));
    }

    // Get the description of a specific token ID
    function getTokenDescription(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return _tokenMetadata[tokenId].description;
    }

    // Get the IPFS hash of a specific token ID
    function getTokenIpfsHash(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return _tokenMetadata[tokenId].ipfsHash;
    }

    // Update the base URI for token metadata (only owner)
    function setBaseTokenURI(string memory baseTokenURI) external onlyOwner {
        _baseTokenURI = baseTokenURI;
    }
}