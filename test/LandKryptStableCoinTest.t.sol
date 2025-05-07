// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/LandKryptStablecoin.sol";

contract LandKryptStablecoinTest is Test {
    LandKryptStablecoin lkusd;
    address owner = address(0x1);
    address nonOwner = address(0x2);
    address minter1 = address(0x3);
    address minter2 = address(0x4);
    address burner1 = address(0x5);
    address burner2 = address(0x6);
    address recipient = address(0x7);
    address zeroAddress = address(0);

    function setUp() public {
        vm.prank(owner);
        lkusd = new LandKryptStablecoin();
    }

    // Initial State Tests
    function testInitialState() public {
        assertEq(lkusd.name(), "LandKrypt Stablecoin");
        assertEq(lkusd.symbol(), "LKUSD");
        assertEq(lkusd.owner(), owner);
        assertEq(lkusd.getAllMinters().length, 0);
        assertEq(lkusd.getAllBurners().length, 0);
    }

    // Minter Management Tests
    function testAddMinter() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);

        assertTrue(lkusd.isMinter(minter1));
        address[] memory minters = lkusd.getAllMinters();
        assertEq(minters.length, 1);
        assertEq(minters[0], minter1);
    }

    function testAddMinterReverts() public {
        // Non-owner cannot add
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lkusd.addMinter(minter1);

        // Cannot add zero address
        vm.prank(owner);
        vm.expectRevert("LandKryptStablecoin: zero address cannot be minter");
        lkusd.addMinter(zeroAddress);

        // Cannot add duplicate
        vm.prank(owner);
        lkusd.addMinter(minter1);
        vm.prank(owner);
        vm.expectRevert("LandKryptStablecoin: address is already minter");
        lkusd.addMinter(minter1);
    }

    function testRemoveMinter() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);
        vm.prank(owner);
        lkusd.addMinter(minter2);

        vm.prank(owner);
        lkusd.removeMinter(minter1);

        assertFalse(lkusd.isMinter(minter1));
        address[] memory minters = lkusd.getAllMinters();
        assertEq(minters.length, 1);
        assertEq(minters[0], minter2);
    }

    function testRemoveMinterReverts() public {
        // Cannot remove non-minter
        vm.prank(owner);
        vm.expectRevert("LandKryptStablecoin: address is not minter");
        lkusd.removeMinter(minter1);

        // Non-owner cannot remove
        vm.prank(owner);
        lkusd.addMinter(minter1);
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        lkusd.removeMinter(minter1);
    }

    // Burner Management Tests
    function testAddBurner() public {
        vm.prank(owner);
        lkusd.addBurner(burner1);

        assertTrue(lkusd.isBurner(burner1));
        address[] memory burners = lkusd.getAllBurners();
        assertEq(burners.length, 1);
        assertEq(burners[0], burner1);
    }

    function testRemoveBurner() public {
        vm.prank(owner);
        lkusd.addBurner(burner1);
        vm.prank(owner);
        lkusd.addBurner(burner2);

        vm.prank(owner);
        lkusd.removeBurner(burner1);

        assertFalse(lkusd.isBurner(burner1));
        address[] memory burners = lkusd.getAllBurners();
        assertEq(burners.length, 1);
        assertEq(burners[0], burner2);
    }

    // Token Operation Tests
    function testMint() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);

        uint256 amount = 1000 ether;
        vm.prank(minter1);
        lkusd.mint(recipient, amount);

        assertEq(lkusd.balanceOf(recipient), amount);
    }

    function testMintReverts() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);

        // Non-minter cannot mint
        vm.prank(nonOwner);
        vm.expectRevert("LandKryptStablecoin: caller is not a minter");
        lkusd.mint(recipient, 1000);

        // Cannot mint to zero address
        vm.prank(minter1);
        vm.expectRevert("ERC20: mint to the zero address");
        lkusd.mint(zeroAddress, 1000);
    }

    function testBurn() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);
        vm.prank(owner);
        lkusd.addBurner(burner1);

        uint256 mintAmount = 1000 ether;
        vm.prank(minter1);
        lkusd.mint(recipient, mintAmount);

        uint256 burnAmount = 500 ether;
        vm.prank(burner1);
        lkusd.burn(recipient, burnAmount);

        assertEq(lkusd.balanceOf(recipient), mintAmount - burnAmount);
    }

    function testBurnReverts() public {
        vm.prank(owner);
        lkusd.addMinter(minter1);
        vm.prank(owner);
        lkusd.addBurner(burner1);

        uint256 amount = 1000 ether;
        vm.prank(minter1);
        lkusd.mint(recipient, amount);

        // Non-burner cannot burn
        vm.prank(nonOwner);
        vm.expectRevert("LandKryptStablecoin: caller is not a burner");
        lkusd.burn(recipient, 500);

        // Cannot burn from zero address
        vm.prank(burner1);
        vm.expectRevert("ERC20: burn from the zero address");
        lkusd.burn(zeroAddress, 500);

        // Cannot burn more than balance
        vm.prank(burner1);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        lkusd.burn(recipient, amount + 1);
    }

    // Edge Cases
    function testMinterArrayMaintenance() public {
        // Add 3 minters
        vm.startPrank(owner);
        lkusd.addMinter(minter1);
        lkusd.addMinter(minter2);
        lkusd.addMinter(burner1);

        // Remove middle minter
        lkusd.removeMinter(minter2);

        address[] memory minters = lkusd.getAllMinters();
        assertEq(minters.length, 2);
        assertTrue(minters[0] == minter1 || minters[1] == minter1);
        assertTrue(minters[0] == burner1 || minters[1] == burner1);
    }

    function testBurnerArrayMaintenance() public {
        // Add 3 burners
        vm.startPrank(owner);
        lkusd.addBurner(burner1);
        lkusd.addBurner(burner2);
        lkusd.addBurner(minter1);

        // Remove middle burner
        lkusd.removeBurner(burner2);

        address[] memory burners = lkusd.getAllBurners();
        assertEq(burners.length, 2);
        assertTrue(burners[0] == burner1 || burners[1] == burner1);
        assertTrue(burners[0] == minter1 || burners[1] == minter1);
    }

    function testMultipleMintersBurners() public {
        vm.startPrank(owner);
        lkusd.addMinter(minter1);
        lkusd.addMinter(minter2);
        lkusd.addBurner(burner1);
        lkusd.addBurner(burner2);

        assertEq(lkusd.getAllMinters().length, 2);
        assertEq(lkusd.getAllBurners().length, 2);

        // Test all minters can mint
        vm.prank(minter1);
        lkusd.mint(recipient, 100);
        vm.prank(minter2);
        lkusd.mint(recipient, 100);

        // Test all burners can burn
        vm.prank(burner1);
        lkusd.burn(recipient, 50);
        vm.prank(burner2);
        lkusd.burn(recipient, 50);
    }
}