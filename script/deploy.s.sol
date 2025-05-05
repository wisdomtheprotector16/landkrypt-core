// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/LandKryptStablecoin.sol";
import "../src/LandKryptStakingToken.sol";
import "../src/RealEstateNFT.sol";
import "../src/DevelopmentContract.sol";
import "../src/NFTStaking.sol";
import "../src/NFTDAO.sol";
import "../src/Exchange.sol";

contract DeployLandKrypt is Script {
    function run() external {
        // Load private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy LandKryptStablecoin (LKUSD)
        LandKryptStablecoin lkusd = new LandKryptStablecoin();
        console.log("LandKryptStablecoin deployed at:", address(lkusd));

        // Deploy LandKryptStakingToken (LKST)
        LandKryptStakingToken lkst = new LandKryptStakingToken();
        console.log("LandKryptStakingToken deployed at:", address(lkst));

        // Deploy RealEstateNFT
        RealEstateNFT realEstateNFT = new RealEstateNFT();
        console.log("RealEstateNFT deployed at:", address(realEstateNFT));

        // Deploy DevelopmentContract
        DevelopmentContract developmentContract = new DevelopmentContract();
        console.log("DevelopmentContract deployed at:", address(developmentContract));

        // Deploy NFTStaking
        NFTStaking nftStaking = new NFTStaking(address(lkusd), address(lkst), 1, 100 ether);
        console.log("NFTStaking deployed at:", address(nftStaking));

        // Deploy NFTDAO
        NFTDAO nftDAO = new NFTDAO(
            address(lkst),
            address(developmentContract),
            address(nftStaking),
            7 days, // Voting period
            20,     // Quorum (20%)
            1 ether // Developer fee
        );
        console.log("NFTDAO deployed at:", address(nftDAO));

        // Deploy Exchange
        Exchange exchange = new Exchange(address(lkusd), address(nftDAO), 50); // 0.5% fee
        console.log("Exchange deployed at:", address(exchange));

        // Set up permissions
        lkst.transferOwnership(address(nftDAO));
        developmentContract.transferOwnership(address(nftDAO));
        console.log("Ownership transferred to NFTDAO.");

        vm.stopBroadcast();
    }
}