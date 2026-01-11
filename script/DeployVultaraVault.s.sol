// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/VultaraVault.sol";

/**
 * @title DeployVultaraVault
 * @notice Deployment script for VultaraVault on Base Sepolia
 * 
 * Usage:
 * forge script script/DeployVultaraVault.s.sol:DeployVultaraVault --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
 */
contract DeployVultaraVault is Script {
    // Base Sepolia USDC Address
    address constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Base Mainnet USDC Address (for future production deploy)
    address constant USDC_BASE_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy VultaraVault with Base Sepolia USDC
        VultaraVault vault = new VultaraVault(
            IERC20(USDC_BASE_SEPOLIA),
            "Vultara USDC Vault",
            "vUSDC"
        );

        console.log("=================================");
        console.log("VultaraVault deployed to:", address(vault));
        console.log("Asset (USDC):", USDC_BASE_SEPOLIA);
        console.log("Name:", vault.name());
        console.log("Symbol:", vault.symbol());
        console.log("Owner:", vault.owner());
        console.log("=================================");

        vm.stopBroadcast();
    }
}
