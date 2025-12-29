// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {TokenBridge} from "../src/TokenBridge.sol";
import {ITokenGateway, TeleportParams} from "@hyperbridge/core/apps/TokenGateway.sol";
import {StateMachine} from "@hyperbridge/core/libraries/StateMachine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Define TokenGatewayParams to match the interface
struct TokenGatewayParams {
    address host;
    address dispatcher;
}

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    bool public transferFromShouldFail;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferFromShouldFail(bool _shouldFail) external {
        transferFromShouldFail = _shouldFail;
    }

    // Override transferFrom to allow testing of transfer failures
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (transferFromShouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

// Mock TokenGateway for testing
// Note: Not implementing ITokenGateway directly to avoid struct type conflicts
contract MockTokenGateway {
    mapping(bytes32 => address) public erc20Assets;
    mapping(bytes32 => address) public erc6160Assets;

    address public host;
    address public dispatcher;

    // Store last teleport params
    uint256 public lastAmount;
    uint256 public lastRelayerFee;
    bytes32 public lastAssetId;
    bool public lastRedeem;
    bytes32 public lastTo;
    bytes public lastDest;
    uint64 public lastTimeout;
    uint256 public lastNativeCost;
    bytes public lastData;

    bool public teleportReverts;

    constructor() {
        host = address(0x1);
        dispatcher = address(0x2);
    }

    function setERC20(bytes32 assetId, address token) external {
        erc20Assets[assetId] = token;
    }

    function setTeleportReverts(bool _reverts) external {
        teleportReverts = _reverts;
    }

    function params() external view returns (TokenGatewayParams memory) {
        return TokenGatewayParams({host: host, dispatcher: dispatcher});
    }

    function erc20(bytes32 assetId) external view returns (address) {
        return erc20Assets[assetId];
    }

    function erc6160(bytes32 assetId) external view returns (address) {
        return erc6160Assets[assetId];
    }

    function instance(bytes calldata destination) external pure returns (address) {
        return address(0);
    }

    // Emit the same event as ITokenGateway for testing
    event AssetTeleported(
        bytes32 to,
        string dest,
        uint256 amount,
        bytes32 commitment,
        address indexed from,
        bytes32 indexed assetId,
        bool redeem
    );

    function teleport(TeleportParams calldata teleportParams) external payable {
        if (teleportReverts) {
            revert("Teleport failed");
        }

        // Store params
        lastAmount = teleportParams.amount;
        lastRelayerFee = teleportParams.relayerFee;
        lastAssetId = teleportParams.assetId;
        lastRedeem = teleportParams.redeem;
        lastTo = teleportParams.to;
        lastDest = teleportParams.dest;
        lastTimeout = teleportParams.timeout;
        lastNativeCost = teleportParams.nativeCost;
        lastData = teleportParams.data;

        emit AssetTeleported(
            teleportParams.to,
            string(teleportParams.dest),
            teleportParams.amount,
            keccak256(abi.encodePacked(block.timestamp, msg.sender)),
            msg.sender,
            teleportParams.assetId,
            teleportParams.redeem
        );
    }

    function getLastTeleportParams() external view returns (TeleportParams memory) {
        return TeleportParams({
            amount: lastAmount,
            relayerFee: lastRelayerFee,
            assetId: lastAssetId,
            redeem: lastRedeem,
            to: lastTo,
            dest: lastDest,
            timeout: lastTimeout,
            nativeCost: lastNativeCost,
            data: lastData
        });
    }
}

contract TokenBridgeTest is Test {
    TokenBridge public tokenBridge;
    MockTokenGateway public mockTokenGateway;
    MockERC20 public mockToken;
    MockERC20 public feeToken;

    address public user = address(0x100);
    address public recipient = address(0x200);

    uint256 public constant DEFAULT_RELAYER_FEE = 1000;
    uint256 public constant INITIAL_BALANCE = 10000 * 10 ** 18;

    event TokensBridged(
        address indexed token,
        bytes32 indexed assetId,
        uint256 amount,
        address indexed sender,
        bytes32 recipient,
        bytes destination,
        bytes32 commitment
    );

    function setUp() public {
        // Deploy mock contracts
        mockTokenGateway = new MockTokenGateway();
        mockToken = new MockERC20("Test Token", "TEST");
        feeToken = new MockERC20("Fee Token", "FEE");

        // Deploy TokenBridge
        tokenBridge = new TokenBridge(address(mockTokenGateway), address(feeToken), DEFAULT_RELAYER_FEE);

        // Setup user with tokens
        vm.startPrank(user);
        mockToken.mint(user, INITIAL_BALANCE);
        feeToken.mint(user, INITIAL_BALANCE);
        vm.stopPrank();

        // Register asset in mock gateway
        bytes32 assetId = keccak256(bytes("TEST"));
        mockTokenGateway.setERC20(assetId, address(mockToken));
    }

    function test_Constructor() public {
        assertEq(address(tokenBridge.tokenGateway()), address(mockTokenGateway));
        assertEq(tokenBridge.feeToken(), address(feeToken));
        assertEq(tokenBridge.defaultRelayerFee(), DEFAULT_RELAYER_FEE);
        assertEq(tokenBridge.DEFAULT_TIMEOUT(), 86400);
    }

    function test_Constructor_RevertsOnZeroTokenGateway() public {
        vm.expectRevert(TokenBridge.ZeroAddress.selector);
        new TokenBridge(address(0), address(feeToken), DEFAULT_RELAYER_FEE);
    }

    function test_Constructor_RevertsOnZeroFeeToken() public {
        vm.expectRevert(TokenBridge.ZeroAddress.selector);
        new TokenBridge(address(mockTokenGateway), address(0), DEFAULT_RELAYER_FEE);
    }

    function test_BridgeTokens_WithSymbol() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111); // Sepolia

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        vm.expectEmit(true, true, true, true);
        emit TokensBridged(
            address(mockToken),
            keccak256(bytes("TEST")),
            amount,
            user,
            bytes32(uint256(uint160(recipient))),
            destChain,
            bytes32(0)
        );

        tokenBridge.bridgeTokens(
            address(mockToken),
            "TEST",
            amount,
            recipient,
            destChain,
            0, // Use default relayer fee
            0, // Use default timeout
            true // Redeem
        );
        vm.stopPrank();

        // Check that tokens were transferred to bridge contract
        assertEq(mockToken.balanceOf(user), INITIAL_BALANCE - amount);
        assertEq(mockToken.balanceOf(address(tokenBridge)), amount); // Tokens are in bridge, approved to gateway
        assertEq(mockToken.allowance(address(tokenBridge), address(mockTokenGateway)), amount);

        // Check teleport params
        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.amount, amount);
        assertEq(params.relayerFee, DEFAULT_RELAYER_FEE);
        assertEq(params.assetId, keccak256(bytes("TEST")));
        assertEq(params.redeem, true);
        assertEq(params.to, bytes32(uint256(uint160(recipient))));
        assertEq(params.timeout, 86400); // DEFAULT_TIMEOUT
    }

    function test_BridgeTokens_ConvenienceFunction() public {
        uint256 amount = 50 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();

        // Check teleport params use defaults
        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.relayerFee, DEFAULT_RELAYER_FEE);
        assertEq(params.redeem, true);
        assertEq(params.timeout, 86400);
    }

    function test_BridgeTokens_WithAssetId() public {
        uint256 amount = 75 * 10 ** 18;
        bytes32 assetId = keccak256(bytes("TEST"));
        bytes memory destChain = StateMachine.evm(11155111);
        uint256 customRelayerFee = 2000;
        uint64 customTimeout = 3600;

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokensWithAssetId(
            address(mockToken),
            assetId,
            amount,
            recipient,
            destChain,
            customRelayerFee,
            customTimeout,
            false // Don't redeem
        );
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.assetId, assetId);
        assertEq(params.relayerFee, customRelayerFee);
        assertEq(params.timeout, customTimeout);
        assertEq(params.redeem, false);
    }

    function test_BridgeTokens_WithCustomRelayerFee() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 customFee = 5000;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain, customFee, 0, true);
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.relayerFee, customFee);
    }

    function test_BridgeTokens_WithCustomTimeout() public {
        uint256 amount = 100 * 10 ** 18;
        uint64 customTimeout = 7200; // 2 hours
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain, 0, customTimeout, true);
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.timeout, customTimeout);
    }

    function test_BridgeTokens_WithNativeValue() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 nativeValue = 1 ether;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.deal(user, nativeValue);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens{value: nativeValue}(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.nativeCost, nativeValue);
    }

    function test_BridgeTokens_FeeTokenApproval() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);
        feeToken.approve(address(tokenBridge), type(uint256).max);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();

        // Fee token should be approved with max amount
        assertEq(feeToken.allowance(address(tokenBridge), address(mockTokenGateway)), type(uint256).max);
    }

    function test_BridgeTokens_WhenTokenIsFeeToken() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        // Use feeToken as the token to bridge
        bytes32 feeAssetId = keccak256(bytes("FEE"));
        mockTokenGateway.setERC20(feeAssetId, address(feeToken));

        vm.startPrank(user);
        feeToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(feeToken), "FEE", amount, recipient, destChain);
        vm.stopPrank();

        // When token == feeToken, no separate fee token approval should happen
        // The approval should only be for the amount being bridged
        assertEq(feeToken.allowance(address(tokenBridge), address(mockTokenGateway)), amount);
    }

    function test_BridgeTokens_RevertsOnZeroAmount() public {
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), 100);

        vm.expectRevert(TokenBridge.InvalidAmount.selector);
        tokenBridge.bridgeTokens(address(mockToken), "TEST", 0, recipient, destChain);
        vm.stopPrank();
    }

    function test_BridgeTokens_RevertsOnZeroRecipient() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        vm.expectRevert(TokenBridge.InvalidRecipient.selector);
        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, address(0), destChain);
        vm.stopPrank();
    }

    function test_BridgeTokens_RevertsOnTransferFailure() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        // Create a token that will fail on transferFrom
        MockERC20 failingToken = new MockERC20("Failing Token", "FAIL");
        failingToken.mint(user, amount);
        failingToken.setTransferFromShouldFail(true);

        // Register the failing token
        bytes32 assetId = keccak256(bytes("FAIL"));
        mockTokenGateway.setERC20(assetId, address(failingToken));

        vm.startPrank(user);
        failingToken.approve(address(tokenBridge), amount);

        vm.expectRevert(TokenBridge.TokenTransferFailed.selector);
        tokenBridge.bridgeTokens(address(failingToken), "FAIL", amount, recipient, destChain);
        vm.stopPrank();
    }

    function test_BridgeTokens_RevertsWhenTeleportFails() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        mockTokenGateway.setTeleportReverts(true);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        vm.expectRevert("Teleport failed");
        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();
    }

    function test_GetAssetId() public {
        bytes32 expectedAssetId = keccak256(bytes("TEST"));
        bytes32 assetId = tokenBridge.getAssetId("TEST");
        assertEq(assetId, expectedAssetId);
    }

    function test_GetERC20Address() public {
        bytes32 assetId = keccak256(bytes("TEST"));
        address erc20Addr = tokenBridge.getERC20Address(assetId);
        assertEq(erc20Addr, address(mockToken));
    }

    function test_SetDefaultRelayerFee() public {
        uint256 newFee = 5000;
        tokenBridge.setDefaultRelayerFee(newFee);
        assertEq(tokenBridge.defaultRelayerFee(), newFee);

        // Test that new fee is used
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.relayerFee, newFee);
    }

    function test_BridgeTokens_DifferentDestinations() public {
        uint256 amount = 100 * 10 ** 18;

        // Test with different destination chains
        bytes[] memory destinations = new bytes[](3);
        destinations[0] = StateMachine.evm(11155111); // Sepolia
        destinations[1] = StateMachine.evm(97); // BSC Testnet
        destinations[2] = StateMachine.polkadot(1000); // Polkadot parachain

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount * destinations.length);

        for (uint256 i = 0; i < destinations.length; i++) {
            tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destinations[i]);

            TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
            assertEq(params.dest, destinations[i]);
        }
        vm.stopPrank();
    }

    function test_BridgeTokens_EventEmitted() public {
        uint256 amount = 100 * 10 ** 18;
        bytes memory destChain = StateMachine.evm(11155111);
        bytes32 expectedAssetId = keccak256(bytes("TEST"));

        vm.startPrank(user);
        mockToken.approve(address(tokenBridge), amount);

        vm.expectEmit(true, true, true, true);
        emit TokensBridged(
            address(mockToken),
            expectedAssetId,
            amount,
            user,
            bytes32(uint256(uint160(recipient))),
            destChain,
            bytes32(0)
        );

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, recipient, destChain);
        vm.stopPrank();
    }

    function testFuzz_BridgeTokens(uint256 amount, address _recipient, uint256 relayerFee, uint64 timeout) public {
        // Bound inputs to valid ranges
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);
        vm.assume(_recipient != address(0));
        vm.assume(timeout <= 31536000); // Max 1 year

        bytes memory destChain = StateMachine.evm(11155111);

        // Ensure user has enough balance
        vm.startPrank(user);
        if (mockToken.balanceOf(user) < amount) {
            mockToken.mint(user, amount);
        }
        mockToken.approve(address(tokenBridge), amount);

        tokenBridge.bridgeTokens(address(mockToken), "TEST", amount, _recipient, destChain, relayerFee, timeout, true);
        vm.stopPrank();

        TeleportParams memory params = mockTokenGateway.getLastTeleportParams();
        assertEq(params.amount, amount);
        assertEq(params.to, bytes32(uint256(uint160(_recipient))));

        if (relayerFee == 0) {
            assertEq(params.relayerFee, DEFAULT_RELAYER_FEE);
        } else {
            assertEq(params.relayerFee, relayerFee);
        }

        if (timeout == 0) {
            assertEq(params.timeout, 86400);
        } else {
            assertEq(params.timeout, timeout);
        }
    }
}

