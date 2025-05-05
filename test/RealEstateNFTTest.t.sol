// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/RealEstateNFT.sol";

contract RealEstateNFTTest is Test {
    RealEstateNFT public nft;
    address public owner = address(0x1);
    address public user = address(0x2);
    string public baseURI = "https://gateway.pinata.cloud/ipfs/";
    string public sampleDescription = "Prime waterfront property";
    string public sampleIpfsHash = "QmXyZ123";

    function setUp() public {
        vm.prank(owner);
        nft = new RealEstateNFT(baseURI);
    }

    // ============ Minting Tests ============
    function test_MintByOwner() public {
        vm.prank(owner);
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);

        assertEq(nft.ownerOf(1), user);
        assertEq(nft.getTokenDescription(1), sampleDescription);
        assertEq(nft.getTokenIpfsHash(1), sampleIpfsHash);
    }

    function test_MintFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);
    }

    function test_MintFailsWithEmptyDescription() public {
        vm.prank(owner);
        vm.expectRevert("Description cannot be empty");
        nft.mint(user, 1, "", sampleIpfsHash);
    }

    function test_MintFailsWithEmptyIpfsHash() public {
        vm.prank(owner);
        vm.expectRevert("IPFS hash cannot be empty");
        nft.mint(user, 1, sampleDescription, "");
    }

    // ============ URI Tests ============
    function test_TokenURI() public {
        vm.prank(owner);
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);

        string memory expectedURI = string(abi.encodePacked(baseURI, sampleIpfsHash));
        assertEq(nft.tokenURI(1), expectedURI);
    }

    function test_TokenURIFailsForNonexistentToken() public {
        vm.expectRevert("ERC721Metadata: URI query for nonexistent token");
        nft.tokenURI(999);
    }

    function test_UpdateBaseURI() public {
        string memory newBaseURI = "https://cloudflare-ipfs.com/ipfs/";
        
        vm.prank(owner);
        nft.setBaseTokenURI(newBaseURI);
        
        vm.prank(owner);
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);

        string memory expectedURI = string(abi.encodePacked(newBaseURI, sampleIpfsHash));
        assertEq(nft.tokenURI(1), expectedURI);
    }

    // ============ Metadata Tests ============
    function test_GetTokenMetadata() public {
        vm.prank(owner);
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);

        assertEq(nft.getTokenDescription(1), sampleDescription);
        assertEq(nft.getTokenIpfsHash(1), sampleIpfsHash);
    }

    function test_GetMetadataFailsForNonexistentToken() public {
        vm.expectRevert("Token does not exist");
        nft.getTokenDescription(999);

        vm.expectRevert("Token does not exist");
        nft.getTokenIpfsHash(999);
    }

    // ============ Fuzz Tests ============
    function testFuzz_MintWithRandomInputs(
        address to,
        uint256 tokenId,
        string memory description,
        string memory ipfsHash
    ) public {
        vm.assume(to != address(0));
        vm.assume(bytes(description).length > 0);
        vm.assume(bytes(ipfsHash).length > 0);

        vm.prank(owner);
        nft.mint(to, tokenId, description, ipfsHash);

        assertEq(nft.ownerOf(tokenId), to);
        assertEq(nft.getTokenDescription(tokenId), description);
        assertEq(nft.getTokenIpfsHash(tokenId), ipfsHash);
    }

    // ============ Edge Cases ============
    function test_MintToZeroAddressFails() public {
        vm.prank(owner);
        vm.expectRevert("ERC721: mint to the zero address");
        nft.mint(address(0), 1, sampleDescription, sampleIpfsHash);
    }

    function test_DuplicateTokenIdFails() public {
        vm.startPrank(owner);
        nft.mint(user, 1, sampleDescription, sampleIpfsHash);
        
        vm.expectRevert("ERC721: token already minted");
        nft.mint(user, 1, "Different description", "Qm987");
        vm.stopPrank();
    }
}