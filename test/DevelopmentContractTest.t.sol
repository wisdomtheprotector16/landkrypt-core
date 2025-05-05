// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/DevelopmentContract.sol";

contract DevelopmentContractTest is Test {
    DevelopmentContract public devContract;
    address owner = address(0x1);
    address developer = address(0x2);
    address otherAccount = address(0x3);
    uint256 landNFTId = 1;
    uint256 ownershipPercentage = 30;
    uint256 projectTimeframe = 86400; // 1 day in seconds

    function setUp() public {
        vm.startPrank(owner);
        devContract = new DevelopmentContract();
        vm.stopPrank();
    }

    // Deployment Tests
    function testDeployment() public {
        assertEq(devContract.owner(), owner);
        assertEq(devContract.name(), "LandKrypt Development Contract");
        assertEq(devContract.symbol(), "LKDC");
        assertEq(devContract.totalSupply(), 0);
    }

    // Minting Functionality
    function testMintDevelopmentContract() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ContractMinted(1, developer, landNFTId, ownershipPercentage, projectTimeframe);
        
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );

        assertEq(devContract.ownerOf(1), developer);
        assertEq(devContract.totalSupply(), 1);

        DevelopmentContract.ContractInfo memory info = devContract.contractInfo(1);
        assertEq(info.developer, developer);
        assertEq(info.landNFTId, landNFTId);
        assertEq(info.ownershipPercentage, ownershipPercentage);
        assertEq(info.projectTimeframe, projectTimeframe);
        assertEq(info.startDate, block.timestamp);

        assertEq(devContract.landToContract(landNFTId), 1);
        assertTrue(devContract.hasDevelopmentContract(landNFTId));
        vm.stopPrank();
    }

    function testMintFailsIfNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
    }

    function testMintFailsIfDuplicateLandNFTId() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );

        vm.expectRevert("Contract already exists for this LandNFT");
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        vm.stopPrank();
    }

    function testMintFailsIfInvalidOwnershipPercentage() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid ownership percentage");
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            101, // >100%
            projectTimeframe
        );

        vm.expectRevert("Invalid ownership percentage");
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            0, // 0%
            projectTimeframe
        );
        vm.stopPrank();
    }

    function testMintFailsIfZeroTimeframe() public {
        vm.startPrank(owner);
        vm.expectRevert("Timeframe must be positive");
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            0
        );
        vm.stopPrank();
    }

    // View Function Tests
    function testHasDevelopmentContract() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        vm.stopPrank();

        assertTrue(devContract.hasDevelopmentContract(landNFTId));
        assertFalse(devContract.hasDevelopmentContract(999)); // Non-existent
    }

    function testGetDeveloper() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        uint256 tokenId = devContract.landToContract(landNFTId);
        vm.stopPrank();

        assertEq(devContract.getDeveloper(tokenId), developer);
        
        vm.expectRevert("Contract does not exist");
        devContract.getDeveloper(999);
    }

    function testIsProjectCompleted() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        uint256 tokenId = devContract.landToContract(landNFTId);
        vm.stopPrank();

        assertFalse(devContract.isProjectCompleted(tokenId));
        
        // Fast forward time
        vm.warp(block.timestamp + projectTimeframe + 1);
        assertTrue(devContract.isProjectCompleted(tokenId));

        vm.expectRevert("Contract does not exist");
        devContract.isProjectCompleted(999);
    }

    function testGetProjectDeadline() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        uint256 tokenId = devContract.landToContract(landNFTId);
        DevelopmentContract.ContractInfo memory info = devContract.contractInfo(tokenId);
        vm.stopPrank();

        uint256 expectedDeadline = info.startDate + info.projectTimeframe;
        assertEq(devContract.getProjectDeadline(tokenId), expectedDeadline);

        vm.expectRevert("Contract does not exist");
        devContract.getProjectDeadline(999);
    }

    // ERC721 Compliance Tests
    function testERC721Compliance() public {
        vm.startPrank(owner);
        devContract.mintDevelopmentContract(
            developer,
            landNFTId,
            ownershipPercentage,
            projectTimeframe
        );
        uint256 tokenId = devContract.landToContract(landNFTId);
        vm.stopPrank();

        // Test transfer
        vm.startPrank(developer);
        devContract.transferFrom(developer, otherAccount, tokenId);
        vm.stopPrank();

        assertEq(devContract.ownerOf(tokenId), otherAccount);
        
        // Verify contract info remains unchanged
        DevelopmentContract.ContractInfo memory info = devContract.contractInfo(tokenId);
        assertEq(info.developer, developer);

        // Test unauthorized transfer
        vm.startPrank(owner);
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        devContract.transferFrom(otherAccount, owner, tokenId);
        vm.stopPrank();
    }

    // Event for testing
    event ContractMinted(
        uint256 indexed tokenId,
        address indexed developer,
        uint256 indexed landNFTId,
        uint256 ownershipPercentage,
        uint256 projectTimeframe
    );
}