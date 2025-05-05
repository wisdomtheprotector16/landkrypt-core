// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/security/ReentrancyGuard.sol";
import "./Oracle.sol";
import "./LandKryptStableCoin.sol";

contract Exchange is ReentrancyGuard {
    LandKryptStablecoin public stablecoin;
    Oracle public oracle;
    address public owner;
    uint256 public feeRate; // Fee rate in basis points (e.g., 50 = 0.5%)

    // Mapping to store Chainlink price feed addresses for ERC20 tokens
    mapping(address => address) public erc20PriceFeeds;

    event SwappedETHForLKUSD(address indexed user, uint256 ethAmount, uint256 lkusdAmount);
    event SwappedERC20ForLKUSD(address indexed user, address indexed erc20Token, uint256 erc20Amount, uint256 lkusdAmount);
    event TokensTransferred(address indexed token, address indexed to, uint256 amount);

    constructor(address _stablecoin, address _oracle, uint256 _feeRate) {
        stablecoin = LandKryptStablecoin(_stablecoin);
        oracle = Oracle(_oracle);
        owner = msg.sender;
        feeRate = _feeRate;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Swap ETH for LKUSD
    function swapETHForLKUSD() external payable nonReentrant {
        require(msg.value > 0, "Must send ETH to swap");

        // Convert ETH to USD
        uint256 ethValueInUSD = oracle.convertETHToUSD(msg.value);

        // Deduct fee
        uint256 fee = (ethValueInUSD * feeRate) / 10000;
        uint256 lkusdAmount = ethValueInUSD - fee;

        // Mint LKUSD to the user
        stablecoin.mint(msg.sender, lkusdAmount);

        emit SwappedETHForLKUSD(msg.sender, msg.value, lkusdAmount);
    }

    // Swap ERC20 for LKUSD
    function swapERC20ForLKUSD(address erc20Token, uint256 erc20Amount) external nonReentrant {
        require(erc20Amount > 0, "Must send ERC20 tokens to swap");

        // Transfer ERC20 tokens from user to this contract
        IERC20(erc20Token).transferFrom(msg.sender, address(this), erc20Amount);

        // Get the price of the ERC20 token in USD
        uint256 erc20ValueInUSD = getERC20PriceInUSD(erc20Token, erc20Amount);

        // Deduct fee
        uint256 fee = (erc20ValueInUSD * feeRate) / 10000;
        uint256 lkusdAmount = erc20ValueInUSD - fee;

        // Mint LKUSD to the user
        stablecoin.mint(msg.sender, lkusdAmount);

        emit SwappedERC20ForLKUSD(msg.sender, erc20Token, erc20Amount, lkusdAmount);
    }

    // Get the price of an ERC20 token in USD using Chainlink price feed
    function getERC20PriceInUSD(address erc20Token, uint256 erc20Amount) internal view returns (uint256) {
        address priceFeedAddress = erc20PriceFeeds[erc20Token];
        require(priceFeedAddress != address(0), "Price feed not found for this token");

        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed");

        // Convert ERC20 amount to USD (assuming price feed returns 8 decimals)
        return (erc20Amount * uint256(price)) / 1e8;
    }

    // Allow owner to set the price feed address for an ERC20 token
    function setERC20PriceFeed(address erc20Token, address priceFeedAddress) external onlyOwner {
        erc20PriceFeeds[erc20Token] = priceFeedAddress;
    }

    // Allow owner to transfer ERC20 tokens out of the contract
    function transferTokens(address erc20Token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        IERC20(erc20Token).transfer(to, amount);
        emit TokensTransferred(erc20Token, to, amount);
    }

    // Withdraw fees collected by the exchange (only owner)
    function withdrawFees(address to) external onlyOwner {
        uint256 balance = stablecoin.balanceOf(address(this));
        require(balance > 0, "No fees to withdraw");
        stablecoin.transfer(to, balance);
    }

    // Update fee rate (only owner)
    function updateFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 1000, "Fee rate cannot exceed 10%");
        feeRate = newFeeRate;
    }
}