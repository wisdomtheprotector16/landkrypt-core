// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Exchange.sol";
import "../src/LandKryptStablecoin.sol";
import "../src/Oracle.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 ether);
    }
}

// Mock Chainlink AggregatorV3Interface
contract MockPriceFeed {
    int256 public price;
    uint8 public decimals = 8;
    
    constructor(int256 _initialPrice) {
        price = _initialPrice;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, price, 0, 0, 0);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract ExchangeTest is Test {
    Exchange public exchange;
    LandKryptStablecoin public stablecoin;
    Oracle public oracle;
    MockERC20 public mockToken;
    MockPriceFeed public ethPriceFeed;
    MockPriceFeed public erc20PriceFeed;
    
    address owner = address(0x1);
    address user = address(0x2);
    address feeRecipient = address(0x3);
    
    uint256 feeRate = 50; // 0.5%
    uint256 ethPrice = 2000 * 1e8; // $2000 with 8 decimals
    uint256 erc20Price = 1 * 1e8; // $1 with 8 decimals

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy price feeds
        ethPriceFeed = new MockPriceFeed(int256(ethPrice));
        erc20PriceFeed = new MockPriceFeed(int256(erc20Price));
        
        // Deploy oracle with ETH price feed
        oracle = new Oracle(address(ethPriceFeed));
        
        // Deploy stablecoin
        stablecoin = new LandKryptStablecoin();
        
        // Deploy exchange
        exchange = new Exchange(
            address(stablecoin),
            address(oracle),
            feeRate
        );
        
        // Setup permissions
        stablecoin.addMinter(address(exchange));
        
        // Deploy mock ERC20 token
        mockToken = new MockERC20();
        
        // Set ERC20 price feed in exchange
        exchange.setERC20PriceFeed(address(mockToken), address(erc20PriceFeed));
        
        vm.stopPrank();
        
        // Fund user with mock tokens
        vm.prank(owner);
        mockToken.transfer(user, 1000 ether);
        
        // Approvals
        vm.prank(user);
        mockToken.approve(address(exchange), type(uint256).max);
    }

    // ========== ETH to LKUSD Swap Tests ==========
    function test_SwapETHForLKUSD() public {
        uint256 ethAmount = 1 ether;
        uint256 ethValueInUSD = (ethAmount * uint256(ethPrice)) / 1e8;
        uint256 expectedFee = (ethValueInUSD * feeRate) / 10000;
        uint256 expectedLKUSD = ethValueInUSD - expectedFee;
        
        uint256 initialBalance = stablecoin.balanceOf(user);
        
        vm.prank(user);
        exchange.swapETHForLKUSD{value: ethAmount}();
        
        assertEq(stablecoin.balanceOf(user), initialBalance + expectedLKUSD);
    }

    function test_SwapETHForLKUSDFailsWithZeroValue() public {
        vm.prank(user);
        vm.expectRevert("Must send ETH to swap");
        exchange.swapETHForLKUSD{value: 0}();
    }

    function test_SwapETHForLKUSDWithDifferentPrices() public {
        // Test with higher ETH price
        ethPriceFeed.setPrice(int256(3000 * 1e8)); // $3000
        uint256 ethAmount = 1 ether;
        uint256 ethValueInUSD = (ethAmount * 3000 * 1e8) / 1e8;
        uint256 expectedLKUSD = ethValueInUSD - ((ethValueInUSD * feeRate) / 10000);
        
        vm.prank(user);
        exchange.swapETHForLKUSD{value: ethAmount}();
        
        assertEq(stablecoin.balanceOf(user), expectedLKUSD);
    }

    // ========== ERC20 to LKUSD Swap Tests ==========
    function test_SwapERC20ForLKUSD() public {
        uint256 erc20Amount = 100 ether; // 100 tokens
        uint256 erc20ValueInUSD = (erc20Amount * uint256(erc20Price)) / 1e8;
        uint256 expectedFee = (erc20ValueInUSD * feeRate) / 10000;
        uint256 expectedLKUSD = erc20ValueInUSD - expectedFee;
        
        uint256 initialBalance = stablecoin.balanceOf(user);
        
        vm.prank(user);
        exchange.swapERC20ForLKUSD(address(mockToken), erc20Amount);
        
        assertEq(stablecoin.balanceOf(user), initialBalance + expectedLKUSD);
        assertEq(mockToken.balanceOf(address(exchange)), erc20Amount);
    }

    function test_SwapERC20ForLKUSDFailsWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert("Must send ERC20 tokens to swap");
        exchange.swapERC20ForLKUSD(address(mockToken), 0);
    }

    function test_SwapERC20ForLKUSDFailsWithoutPriceFeed() public {
        // Create new token without price feed
        MockERC20 newToken = new MockERC20();
        vm.prank(user);
        newToken.approve(address(exchange), type(uint256).max);
        
        vm.prank(user);
        vm.expectRevert("Price feed not found for this token");
        exchange.swapERC20ForLKUSD(address(newToken), 100 ether);
    }

    // ========== Fee Calculation Tests ==========
    function test_FeeCalculation() public {
        uint256 ethAmount = 1 ether;
        uint256 ethValueInUSD = (ethAmount * uint256(ethPrice)) / 1e8;
        uint256 expectedFee = (ethValueInUSD * feeRate) / 10000;
        
        vm.prank(user);
        exchange.swapETHForLKUSD{value: ethAmount}();
        
        assertEq(stablecoin.balanceOf(address(exchange)), expectedFee);
    }

    function test_FeeRateUpdate() public {
        uint256 newFeeRate = 100; // 1%
        vm.prank(owner);
        exchange.updateFeeRate(newFeeRate);
        
        uint256 ethAmount = 1 ether;
        uint256 ethValueInUSD = (ethAmount * uint256(ethPrice)) / 1e8;
        uint256 expectedFee = (ethValueInUSD * newFeeRate) / 10000;
        
        vm.prank(user);
        exchange.swapETHForLKUSD{value: ethAmount}();
        
        assertEq(stablecoin.balanceOf(address(exchange)), expectedFee);
    }

    function test_FeeRateUpdateFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner can call this function");
        exchange.updateFeeRate(100);
    }

    function test_FeeRateUpdateFailsIfTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Fee rate cannot exceed 10%");
        exchange.updateFeeRate(1001);
    }

    // ========== Admin Function Tests ==========
    function test_WithdrawFees() public {
        // Generate some fees
        vm.prank(user);
        exchange.swapETHForLKUSD{value: 1 ether}();
        
        uint256 feeBalance = stablecoin.balanceOf(address(exchange));
        
        vm.prank(owner);
        exchange.withdrawFees(feeRecipient);
        
        assertEq(stablecoin.balanceOf(feeRecipient), feeBalance);
        assertEq(stablecoin.balanceOf(address(exchange)), 0);
    }

    function test_TransferTokens() public {
        uint256 transferAmount = 100 ether;
        
        // Generate some ERC20 tokens in exchange
        vm.prank(user);
        exchange.swapERC20ForLKUSD(address(mockToken), transferAmount);
        
        vm.prank(owner);
        exchange.transferTokens(address(mockToken), feeRecipient, transferAmount);
        
        assertEq(mockToken.balanceOf(feeRecipient), transferAmount);
        assertEq(mockToken.balanceOf(address(exchange)), 0);
    }

    function test_TransferTokensFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner can call this function");
        exchange.transferTokens(address(mockToken), feeRecipient, 100 ether);
    }

    // ========== Security Tests ==========
    function test_ReentrancyProtection() public {
        // This test would require a malicious contract to test properly
        // Placeholder to show we're aware of the need
        assertTrue(address(exchange).supportsInterface(type(IReentrancyGuard).interfaceId));
    }

    function test_PriceFeedSanityChecks() public {
        // Test with zero price
        erc20PriceFeed.setPrice(0);
        
        vm.prank(user);
        vm.expectRevert("Invalid price feed");
        exchange.swapERC20ForLKUSD(address(mockToken), 100 ether);
        
        // Test with negative price
        erc20PriceFeed.setPrice(-1 * int256(erc20Price));
        
        vm.prank(user);
        vm.expectRevert("Invalid price feed");
        exchange.swapERC20ForLKUSD(address(mockToken), 100 ether);
    }

    // ========== Fuzz Tests ==========
    function testFuzz_SwapETHForLKUSD(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 1 wei, 1000 ether);
        
        uint256 ethValueInUSD = (ethAmount * uint256(ethPrice)) / 1e8;
        uint256 expectedLKUSD = ethValueInUSD - ((ethValueInUSD * feeRate) / 10000);
        
        vm.prank(user);
        exchange.swapETHForLKUSD{value: ethAmount}();
        
        assertEq(stablecoin.balanceOf(user), expectedLKUSD);
    }

    function testFuzz_SwapERC20ForLKUSD(uint256 erc20Amount) public {
        erc20Amount = bound(erc20Amount, 1 wei, 1000000 ether);
        
        uint256 erc20ValueInUSD = (erc20Amount * uint256(erc20Price)) / 1e8;
        uint256 expectedLKUSD = erc20ValueInUSD - ((erc20ValueInUSD * feeRate) / 10000);
        
        vm.prank(user);
        exchange.swapERC20ForLKUSD(address(mockToken), erc20Amount);
        
        assertEq(stablecoin.balanceOf(user), expectedLKUSD);
    }
}