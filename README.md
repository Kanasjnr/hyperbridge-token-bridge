# Hyperbridge Token Bridge

A cross-chain token bridge implementation using Hyperbridge SDK that enables ERC20 token transfers between different chains in the Polkadot ecosystem and EVM-compatible chains.

## Overview

This project implements a TokenBridge contract that wraps Hyperbridge's TokenGateway interface to provide a simplified API for bridging tokens across chains. The bridge supports transfers between various networks including Polkadot parachains, Ethereum testnets, BSC Testnet, and Optimism Sepolia.

## What the Contract Does

### TokenBridge Contract

The `TokenBridge` contract acts as a wrapper around Hyperbridge's `TokenGateway`, simplifying the process of cross-chain token transfers. Here's what it does:

1. **Token Custody**: When a user wants to bridge tokens, the contract:
   - Receives tokens from the user via `transferFrom`
   - Approves the TokenGateway to spend those tokens
   - Handles fee token approvals separately

2. **Cross-Chain Transfer Initiation**: The contract:
   - Generates an `assetId` from the token symbol (using keccak256 hash)
   - Converts the recipient address to bytes32 format (required for cross-chain compatibility)
   - Constructs `TeleportParams` with all necessary parameters
   - Calls the TokenGateway's `teleport()` function to initiate the cross-chain transfer

3. **Parameter Management**:
   - Uses default relayer fee if none is provided
   - Uses default timeout (24 hours) if none is specified
   - Supports custom fees and timeouts
   - Handles native token payments for gateway fees

4. **Asset ID Generation**: The contract automatically generates asset IDs from token symbols using `keccak256(bytes(symbol))`, which matches Hyperbridge's asset identification system.

### Key Features

- **Multiple Bridge Functions**: 
  - `bridgeTokens()` with full parameter control
  - `bridgeTokens()` convenience function with defaults
  - `bridgeTokensWithAssetId()` for pre-computed asset IDs

- **Flexible Configuration**:
  - Configurable default relayer fee
  - Custom timeout support
  - Native token fee payment option

- **Error Handling**:
  - Validates amounts (must be > 0)
  - Validates recipient addresses (cannot be zero)
  - Handles token transfer failures
  - Validates constructor parameters

- **Helper Functions**:
  - `getAssetId()`: Compute assetId from symbol
  - `getERC20Address()`: Query ERC20 address for an assetId
  - `setDefaultRelayerFee()`: Update default relayer fee

## How It Works

1. **User Approval**: User approves the TokenBridge contract to spend their tokens
2. **Token Transfer**: Contract transfers tokens from user to itself
3. **Gateway Approval**: Contract approves TokenGateway to spend the tokens
4. **Teleport Initiation**: Contract calls TokenGateway.teleport() with properly formatted parameters
5. **Cross-Chain Processing**: Hyperbridge handles the actual cross-chain message passing and token minting/burning on the destination chain

## Architecture

```
User -> TokenBridge -> TokenGateway -> Hyperbridge -> Destination Chain
```

The TokenBridge contract sits between users and the TokenGateway, providing:
- Simplified API (symbol-based instead of assetId-based)
- Default parameter handling
- Better error messages
- Event tracking

## Supported Networks

The bridge supports transfers between:
- Paseo (Polkadot testnet)
- Ethereum Sepolia
- BSC Testnet
- Optimism Sepolia
- Other EVM-compatible chains via StateMachine identifiers

## Project Structure

```
.
├── src/
│   └── TokenBridge.sol          # Main bridge contract
├── test/
│   └── TokenBridge.t.sol        # Comprehensive test suite
├── script/                      # Deployment scripts (to be added)
└── lib/                         # Dependencies
    ├── hyperbridge-sdk/         # Hyperbridge SDK
    └── openzeppelin-contracts/  # OpenZeppelin contracts
```

## Installation

### Prerequisites

- Node.js >= 22
- Foundry
- pnpm (optional, for SDK development)

### Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd hyperbridge-token-bridge
```

2. Install dependencies (already included as git submodules):
```bash
forge install
```

3. Build the project:
```bash
forge build
```

## Usage

### Testing

Run the test suite:
```bash
forge test
```

Run tests with gas reporting:
```bash
forge test --gas-report
```

Run specific test:
```bash
forge test --match-test test_BridgeTokens_WithSymbol
```

### Building

```bash
forge build
```

### Formatting

```bash
forge fmt
```

### Deployment

Deployment scripts will be added in the `script/` directory. Example:

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

## Contract Interface

### Main Functions

#### bridgeTokens (with symbol)
```solidity
function bridgeTokens(
    address token,
    string memory symbol,
    uint256 amount,
    address recipient,
    bytes memory destChain,
    uint256 relayerFee,
    uint64 timeout,
    bool redeem
) external payable
```

#### bridgeTokens (convenience)
```solidity
function bridgeTokens(
    address token,
    string memory symbol,
    uint256 amount,
    address recipient,
    bytes memory destChain
) external payable
```

#### bridgeTokensWithAssetId
```solidity
function bridgeTokensWithAssetId(
    address token,
    bytes32 assetId,
    uint256 amount,
    address recipient,
    bytes memory destChain,
    uint256 relayerFee,
    uint64 timeout,
    bool redeem
) external payable
```

### Helper Functions

- `getAssetId(string memory symbol)`: Returns the assetId for a given symbol
- `getERC20Address(bytes32 assetId)`: Returns the ERC20 address for an assetId
- `setDefaultRelayerFee(uint256 newRelayerFee)`: Updates the default relayer fee

## Testing

The test suite includes 21 comprehensive tests covering:

- Constructor validation
- Token bridging with various parameters
- Error handling (zero amounts, zero recipients, transfer failures)
- Fee token handling
- Different destination chains
- Event emission
- Helper functions
- Fuzz testing

All tests pass successfully.

## Development

### Adding New Features

1. Make changes to `src/TokenBridge.sol`
2. Add corresponding tests in `test/TokenBridge.t.sol`
3. Run `forge test` to verify
4. Format code with `forge fmt`

### Dependencies

- `@hyperbridge/core`: Hyperbridge SDK core contracts
- `@openzeppelin/contracts`: OpenZeppelin contract library

## Resources

- [Hyperbridge Documentation](https://docs.hyperbridge.network/)
- [Hyperbridge SDK GitHub](https://github.com/polytope-labs/hyperbridge-sdk)
- [XCM Documentation](https://wiki.polkadot.com/learn/learn-xcm/)
- [Foundry Book](https://book.getfoundry.sh/)

## License

MIT
