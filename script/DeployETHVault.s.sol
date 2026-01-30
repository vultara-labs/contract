// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/VultaraETHVault.sol";

/**
 * @title DeployVultaraETHVault
 * @notice Deployment script for VultaraETHVault on Base Mainnet
 * 
 * Usage:
 * forge script script/DeployETHVault.s.sol:DeployVultaraETHVault --rpc-url https://mainnet.base.org --broadcast --verify
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
        console.log("OptionBook Linked:", vault.OPTION_BOOK());
        console.log("=================================");

        vm.stopBroadcast();
    }
}
