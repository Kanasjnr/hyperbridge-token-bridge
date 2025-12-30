// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {TokenBridge} from "../src/TokenBridge.sol";

/**
 * @title DeploySepolia
 * @notice Deployment script for Ethereum Sepolia testnet
 */
contract DeploySepolia is Script {
    // Ethereum Sepolia - Gargantua V3
    address constant TOKEN_GATEWAY = 0xFcDa26cA021d5535C3059547390E6cCd8De7acA6;
    address constant FEE_TOKEN = 0xA801da100bF16D07F668F4A49E1f71fc54D05177; // USD.h
    uint256 constant DEFAULT_RELAYER_FEE = 1000; // Adjust as needed

    function run() public returns (TokenBridge) {
        
        vm.startBroadcast();

        console.log("Deploying TokenBridge to Ethereum Sepolia");
        console.log("TokenGateway:", vm.toString(TOKEN_GATEWAY));
        console.log("FeeToken:", vm.toString(FEE_TOKEN));
        console.log("Default Relayer Fee:", DEFAULT_RELAYER_FEE);

        TokenBridge tokenBridge = new TokenBridge(
            TOKEN_GATEWAY,
            FEE_TOKEN,
            DEFAULT_RELAYER_FEE
        );

        vm.stopBroadcast();

        console.log("TokenBridge deployed at:", vm.toString(address(tokenBridge)));
        console.log("Network: Ethereum Sepolia (Chain ID: 11155111)");
        console.log("StateMachine: EVM-11155111");

        return tokenBridge;
    }
}

