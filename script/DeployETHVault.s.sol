// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/VultaraETHVault.sol";

/**
 * @title DeployVultaraETHVault
 * @notice Deployment script for VultaraETHVault on Base Sepolia
 * 
 * Usage:
 * forge script script/DeployETHVault.s.sol:DeployVultaraETHVault --rpc-url $BASE_SEPOLIA_RPC --broadcast
 */
contract DeployVultaraETHVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy VultaraETHVault
        VultaraETHVault vault = new VultaraETHVault();

        console.log("=================================");
        console.log("VultaraETHVault deployed to:", address(vault));
        console.log("Name:", vault.name());
        console.log("Symbol:", vault.symbol());
        console.log("Owner:", vault.owner());
        console.log("Min Deposit:", vault.MIN_DEPOSIT());
        console.log("=================================");

        vm.stopBroadcast();
    }
}
