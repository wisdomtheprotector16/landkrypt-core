// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/LandKryptStakingToken.sol";

contract LandKryptStakingTokenTest is Test {
    LandKryptStakingToken token;
    address owner = address(1);
    address minter = address(2);
    address burner = address(3);
    address otherAccount = address(4);

    function setUp() public {
        vm.prank(owner);
        token = new LandKryptStakingToken();
    }

    function testInitialState() public {
        assertEq(token.name(), "LandKrypt Staking Token");
        assertEq(token.symbol(), "LKST");
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 0);
    }

    function testMinterManagement() public {
        // Test adding minter
        vm.prank(owner);
        token.addMinter(minter);
        assertTrue(token.isMinter(minter));
        
        // Test minter list
        address[] memory minters = token.getAllMinters();
        assertEq(minters.length, 1);
        assertEq(minters[0], minter);

        // Test duplicate minter
        vm.prank(owner);
        vm.expectRevert("LandKryptStakingToken: address is already minter");
        token.addMinter(minter);

        // Test non-owner adding minter
        vm.prank(otherAccount);
        vm.expectRevert("Ownable: caller is not the owner");
        token.addMinter(otherAccount);

        // Test removing minter
        vm.prank(owner);
        token.removeMinter(minter);
        assertFalse(token.isMinter(minter));
        assertEq(token.getAllMinters().length, 0);

        // Test removing non-minter
        vm.prank(owner);
        vm.expectRevert("LandKryptStakingToken: address is not minter");
        token.removeMinter(minter);
    }

    function testBurnerManagement() public {
        // Test adding burner
        vm.prank(owner);
        token.addBurner(burner);
        assertTrue(token.isBurner(burner));
        
        // Test burner list
        address[] memory burners = token.getAllBurners();
        assertEq(burners.length, 1);
        assertEq(burners[0], burner);

        // Test duplicate burner
        vm.prank(owner);
        vm.expectRevert("LandKryptStakingToken: address is already burner");
        token.addBurner(burner);

        // Test non-owner adding burner
        vm.prank(otherAccount);
        vm.expectRevert("Ownable: caller is not the owner");
        token.addBurner(otherAccount);

        // Test removing burner
        vm.prank(owner);
        token.removeBurner(burner);
        assertFalse(token.isBurner(burner));
        assertEq(token.getAllBurners().length, 0);

        // Test removing non-burner
        vm.prank(owner);
        vm.expectRevert("LandKryptStakingToken: address is not burner");
        token.removeBurner(burner);
    }

    function testMinting() public {
        vm.prank(owner);
        token.addMinter(minter);

        uint256 amount = 100 ether;
        
        // Test successful mint
        vm.prank(minter);
        token.mint(otherAccount, amount);
        assertEq(token.balanceOf(otherAccount), amount);
        assertEq(token.totalSupply(), amount);

        // Test non-minter minting
        vm.prank(burner);
        vm.expectRevert("LandKryptStakingToken: caller is not a minter");
        token.mint(otherAccount, amount);

        // Test minting to zero address
        vm.prank(minter);
        vm.expectRevert("ERC20: mint to the zero address");
        token.mint(address(0), amount);
    }

    function testBurning() public {
        vm.prank(owner);
        token.addMinter(minter);
        vm.prank(owner);
        token.addBurner(burner);

        uint256 mintAmount = 100 ether;
        uint256 burnAmount = 50 ether;
        
        // Mint tokens first
        vm.prank(minter);
        token.mint(otherAccount, mintAmount);

        // Test successful burn
        vm.prank(burner);
        token.burn(otherAccount, burnAmount);
        assertEq(token.balanceOf(otherAccount), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);

        // Test non-burner burning
        vm.prank(minter);
        vm.expectRevert("LandKryptStakingToken: caller is not a burner");
        token.burn(otherAccount, burnAmount);

        // Test burning from zero address
        vm.prank(burner);
        vm.expectRevert("ERC20: burn from the zero address");
        token.burn(address(0), burnAmount);

        // Test burning more than balance
        vm.prank(burner);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(otherAccount, mintAmount + 1);
    }

    function testMultipleMintersBurners() public {
        address newMinter1 = address(5);
        address newMinter2 = address(6);
        address newBurner1 = address(7);
        address newBurner2 = address(8);

        // Add multiple minters
        vm.startPrank(owner);
        token.addMinter(minter);
        token.addMinter(newMinter1);
        token.addMinter(newMinter2);
        
        // Add multiple burners
        token.addBurner(burner);
        token.addBurner(newBurner1);
        token.addBurner(newBurner2);
        vm.stopPrank();

        // Verify minters
        address[] memory minters = token.getAllMinters();
        assertEq(minters.length, 3);
        
        // Verify burners
        address[] memory burners = token.getAllBurners();
        assertEq(burners.length, 3);

        // Remove some
        vm.prank(owner);
        token.removeMinter(newMinter1);
        vm.prank(owner);
        token.removeBurner(newBurner2);

        // Verify updated lists
        assertEq(token.getAllMinters().length, 2);
        assertEq(token.getAllBurners().length, 2);
        assertFalse(token.isMinter(newMinter1));
        assertFalse(token.isBurner(newBurner2));
    }
}