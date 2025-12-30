// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {TokenBridge} from "../src/TokenBridge.sol";

contract DeployScript is Script {
    // Network configurations
    struct NetworkConfig {
        address tokenGateway;
        address feeToken;
        uint256 defaultRelayerFee;
    }

    // Network configurations mapping
    mapping(string => NetworkConfig) public networks;

    function setUp() public {
        // Ethereum Sepolia configuration
        networks["sepolia"] = NetworkConfig({
            tokenGateway: 0xFcDa26cA021d5535C3059547390E6cCd8De7acA6,
            feeToken: 0xA801da100bF16D07F668F4A49E1f71fc54D05177,
            defaultRelayerFee: 1000 // Adjust based on network requirements
        });

        // Base Sepolia configuration
        networks["base-sepolia"] = NetworkConfig({
            tokenGateway: 0xFcDa26cA021d5535C3059547390E6cCd8De7acA6,
            feeToken: 0xA801da100bF16D07F668F4A49E1f71fc54D05177,
            defaultRelayerFee: 1000 // Adjust based on network requirements
        });
    }

    function run() public returns (TokenBridge) {
        // Get network name from environment or use default
        string memory network = vm.envOr("NETWORK", string("sepolia"));
        
        NetworkConfig memory config = networks[network];
        
        require(config.tokenGateway != address(0), "Invalid network configuration");

        console.log("Deploying TokenBridge to:", network);
        console.log("TokenGateway:", vm.toString(config.tokenGateway));
        console.log("FeeToken:", vm.toString(config.feeToken));
        console.log("Default Relayer Fee:", config.defaultRelayerFee);

        vm.startBroadcast();

        TokenBridge tokenBridge = new TokenBridge(
            config.tokenGateway,
            config.feeToken,
            config.defaultRelayerFee
        );

        vm.stopBroadcast();

        console.log("TokenBridge deployed at:", vm.toString(address(tokenBridge)));
        console.log("Deployment successful!");

        return tokenBridge;
    }

    // Helper function to deploy to a specific network
    function deployToSepolia() public returns (TokenBridge) {
        vm.setEnv("NETWORK", "sepolia");
        return run();
    }

    // Helper function to deploy to Base Sepolia
    function deployToBaseSepolia() public returns (TokenBridge) {
        vm.setEnv("NETWORK", "base-sepolia");
        return run();
    }
}

