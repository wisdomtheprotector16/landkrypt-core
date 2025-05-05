// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Oracle.sol";

// Mock Chainlink AggregatorV3Interface
contract MockPriceFeed is AggregatorV3Interface {
    uint80 public roundId;
    int256 public price;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;
    
    constructor(int256 _initialPrice) {
        setPrice(_initialPrice);
    }

    function setPrice(int256 _price) public {
        price = _price;
        roundId += 1;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = roundId;
    }

    function latestRoundData() external view returns (
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) {
        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }

    // Unused functions in our tests
    function decimals() external pure returns (uint8) { return 8; }
    function description() external pure returns (string memory) { return "Mock ETH/USD"; }
    function version() external pure returns (uint256) { return 1; }
    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not implemented");
    }
}

contract OracleTest is Test {
    Oracle public oracle;
    MockPriceFeed public mockPriceFeed;
    
    // Test values
    int256 public constant INITIAL_PRICE = 2000 * 1e8; // $2000 with 8 decimals
    uint256 public constant TEST_ETH_AMOUNT = 1 ether;

    function setUp() public {
        mockPriceFeed = new MockPriceFeed(INITIAL_PRICE);
        oracle = new Oracle(address(mockPriceFeed));
    }

    // ========== Core Functionality Tests ==========
    function test_GetLatestETHPrice() public {
        int256 price = oracle.getLatestETHPrice();
        assertEq(price, INITIAL_PRICE);
    }

    function test_ConvertETHToUSD() public {
        uint256 usdValue = oracle.convertETHToUSD(TEST_ETH_AMOUNT);
        uint256 expectedValue = (TEST_ETH_AMOUNT * uint256(INITIAL_PRICE)) / 1e8;
        assertEq(usdValue, expectedValue);
    }

    // ========== Edge Case Tests ==========
    function test_RevertsOnZeroPrice() public {
        mockPriceFeed.setPrice(0);
        vm.expectRevert("Invalid price feed");
        oracle.convertETHToUSD(TEST_ETH_AMOUNT);
    }

    function test_RevertsOnNegativePrice() public {
        mockPriceFeed.setPrice(-100 * 1e8);
        vm.expectRevert("Invalid price feed");
        oracle.convertETHToUSD(TEST_ETH_AMOUNT);
    }

    function test_HandlesPriceUpdates() public {
        int256 newPrice = 2500 * 1e8; // $2500
        mockPriceFeed.setPrice(newPrice);
        
        uint256 usdValue = oracle.convertETHToUSD(TEST_ETH_AMOUNT);
        uint256 expectedValue = (TEST_ETH_AMOUNT * uint256(newPrice)) / 1e8;
        assertEq(usdValue, expectedValue);
    }

    function test_HandlesSmallEthAmounts() public {
        uint256 smallAmount = 1 wei;
        uint256 usdValue = oracle.convertETHToUSD(smallAmount);
        uint256 expectedValue = (smallAmount * uint256(INITIAL_PRICE)) / 1e8;
        assertEq(usdValue, expectedValue);
    }

    // ========== Fuzz Tests ==========
    function testFuzz_ConvertETHToUSD(uint256 ethAmount) public {
        // Bound to reasonable values to prevent overflow
        ethAmount = bound(ethAmount, 1 wei, 1_000_000 ether);
        
        uint256 usdValue = oracle.convertETHToUSD(ethAmount);
        uint256 expectedValue = (ethAmount * uint256(INITIAL_PRICE)) / 1e8;
        assertEq(usdValue, expectedValue);
    }

    function testFuzz_PriceUpdates(int256 price) public {
        // Bound price to positive values that won't overflow
        price = bound(price, 1, type(int256).max / int256(TEST_ETH_AMOUNT));
        
        mockPriceFeed.setPrice(price);
        uint256 usdValue = oracle.convertETHToUSD(TEST_ETH_AMOUNT);
        uint256 expectedValue = (TEST_ETH_AMOUNT * uint256(price)) / 1e8;
        assertEq(usdValue, expectedValue);
    }

    // ========== Integration Tests ==========
    function test_PriceFeedDecimalsHandling() public {
        // Test with different decimal configurations
        int256 priceWith18Decimals = 2000 * 1e18;
        mockPriceFeed.setPrice(priceWith18Decimals);
        
        // Should still work because we're using the raw value
        int256 rawPrice = oracle.getLatestETHPrice();
        assertEq(rawPrice, priceWith18Decimals);
    }
}