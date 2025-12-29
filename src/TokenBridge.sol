// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ITokenGateway, TeleportParams} from "@hyperbridge/core/apps/TokenGateway.sol";
import {StateMachine} from "@hyperbridge/core/libraries/StateMachine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenBridge
 * @notice A contract that enables cross-chain token transfers using Hyperbridge's TokenGateway
 * @dev This contract wraps the TokenGateway interface to provide a simpler API for bridging tokens
 */
contract TokenBridge {
    ITokenGateway public immutable tokenGateway;
    address public immutable feeToken;

    /// @notice Default timeout for cross-chain transfers (24 hours)
    uint64 public constant DEFAULT_TIMEOUT = 86400;

    /// @notice Default relayer fee (can be overridden)
    uint256 public defaultRelayerFee;

    /// @notice Event emitted when tokens are bridged
    event TokensBridged(
        address indexed token,
        bytes32 indexed assetId,
        uint256 amount,
        address indexed sender,
        bytes32 recipient,
        bytes destination,
        bytes32 commitment
    );

    /// @notice Error thrown when token transfer fails
    error TokenTransferFailed();

    /// @notice Error thrown when invalid amount is provided
    error InvalidAmount();

    /// @notice Error thrown when invalid recipient is provided
    error InvalidRecipient();

    /// @notice Error thrown when zero address is provided
    error ZeroAddress();

    constructor(address _tokenGateway, address _feeToken, uint256 _defaultRelayerFee) {
        if (_tokenGateway == address(0)) revert ZeroAddress();
        if (_feeToken == address(0)) revert ZeroAddress();

        tokenGateway = ITokenGateway(_tokenGateway);
        feeToken = _feeToken;
        defaultRelayerFee = _defaultRelayerFee;
    }

    /**
     * @notice Internal function to handle the actual bridging logic
     * @param token The token address to bridge
     * @param assetId The asset identifier
     * @param amount The amount to bridge
     * @param recipient The recipient address on the destination chain
     * @param destChain The destination chain identifier
     * @param relayerFee The fee to pay the relayer
     * @param timeout The timeout in seconds for the request
     * @param redeem Whether to redeem ERC20 on the destination
     */
    function _bridgeTokens(
        address token,
        bytes32 assetId,
        uint256 amount,
        address recipient,
        bytes memory destChain,
        uint256 relayerFee,
        uint64 timeout,
        bool redeem
    ) internal {
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();

        // Transfer tokens from user to this contract
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TokenTransferFailed();

        // Approve tokenGateway to spend tokens
        IERC20(token).approve(address(tokenGateway), amount);

        // Approve fee token if different from the token being bridged
        if (feeToken != token) {
            // Approve max amount for fee token to avoid repeated approvals
            IERC20(feeToken).approve(address(tokenGateway), type(uint256).max);
        }

        // Convert recipient address to bytes32 (left-padded for EVM chains)
        bytes32 recipientBytes32 = bytes32(uint256(uint160(recipient)));

        // Use provided relayerFee or default
        uint256 finalRelayerFee = relayerFee == 0 ? defaultRelayerFee : relayerFee;

        // Use provided timeout or default
        uint64 finalTimeout = timeout == 0 ? DEFAULT_TIMEOUT : timeout;

        // Prepare teleport parameters
        TeleportParams memory teleportParams = TeleportParams({
            amount: amount,
            relayerFee: finalRelayerFee,
            assetId: assetId,
            redeem: redeem,
            to: recipientBytes32,
            dest: destChain,
            timeout: finalTimeout,
            nativeCost: msg.value, // Use native token sent with transaction for fees
            data: "" // Empty data for simple token transfers
        });

        // Initiate the cross-chain transfer
        tokenGateway.teleport{value: msg.value}(teleportParams);

        // Emit event for tracking
        // Note: We can't get the commitment from the call, but the TokenGateway will emit AssetTeleported
        emit TokensBridged(
            token,
            assetId,
            amount,
            msg.sender,
            recipientBytes32,
            destChain,
            bytes32(0) // Commitment will be in TokenGateway's AssetTeleported event
        );
    }

    /**
     * @notice Bridge tokens to another chain
     * @param token The token address to bridge
     * @param symbol The token symbol to bridge (used to generate assetId)
     * @param amount The amount to bridge
     * @param recipient The recipient address on the destination chain
     * @param destChain The destination chain identifier (e.g., StateMachine.evm(11155111) for Sepolia)
     * @param relayerFee The fee to pay the relayer (0 to use default)
     * @param timeout The timeout in seconds for the request (0 to use default)
     * @param redeem Whether to redeem ERC20 on the destination (true) or mint hyper-fungible token (false)
     */
    function bridgeTokens(
        address token,
        string memory symbol,
        uint256 amount,
        address recipient,
        bytes memory destChain,
        uint256 relayerFee,
        uint64 timeout,
        bool redeem
    ) external payable {
        // Generate assetId from symbol (keccak256 hash)
        bytes32 assetId = keccak256(bytes(symbol));
        _bridgeTokens(token, assetId, amount, recipient, destChain, relayerFee, timeout, redeem);
    }

    /**
     * @notice Convenience function with default parameters
     * @param token The token address to bridge
     * @param symbol The token symbol to bridge
     * @param amount The amount to bridge
     * @param recipient The recipient address on the destination chain
     * @param destChain The destination chain identifier
     */
    function bridgeTokens(
        address token,
        string memory symbol,
        uint256 amount,
        address recipient,
        bytes memory destChain
    ) external payable {
        // Generate assetId from symbol (keccak256 hash)
        bytes32 assetId = keccak256(bytes(symbol));
        _bridgeTokens(token, assetId, amount, recipient, destChain, 0, 0, true);
    }

    /**
     * @notice Bridge tokens using a pre-computed assetId
     * @param token The token address to bridge
     * @param assetId The pre-computed asset identifier
     * @param amount The amount to bridge
     * @param recipient The recipient address on the destination chain
     * @param destChain The destination chain identifier
     * @param relayerFee The fee to pay the relayer (0 to use default)
     * @param timeout The timeout in seconds for the request (0 to use default)
     * @param redeem Whether to redeem ERC20 on the destination (true) or mint hyper-fungible token (false)
     */
    function bridgeTokensWithAssetId(
        address token,
        bytes32 assetId,
        uint256 amount,
        address recipient,
        bytes memory destChain,
        uint256 relayerFee,
        uint64 timeout,
        bool redeem
    ) external payable {
        _bridgeTokens(token, assetId, amount, recipient, destChain, relayerFee, timeout, redeem);
    }

    /**
     * @notice Update the default relayer fee
     * @param newRelayerFee The new default relayer fee
     */
    function setDefaultRelayerFee(uint256 newRelayerFee) external {
        defaultRelayerFee = newRelayerFee;
    }

    /**
     * @notice Get the assetId for a given symbol
     * @param symbol The token symbol
     * @return The assetId (keccak256 hash of symbol)
     */
    function getAssetId(string memory symbol) external pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }

    /**
     * @notice Get the ERC20 address for a given assetId
     * @param assetId The asset identifier
     * @return The ERC20 token address
     */
    function getERC20Address(bytes32 assetId) external view returns (address) {
        return tokenGateway.erc20(assetId);
    }
}

