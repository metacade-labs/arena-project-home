// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {ProjectHomeRegistry} from "../src/ProjectHomeRegistry.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";

/// @notice The deploy path is chain-aware. These tests run the real script under each
///         chain id and assert what it would send, without touching any network.
contract DeployTest is Test {
    address internal constant MAINNET_NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    address internal constant MAINNET_NVDA_TOKEN = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    string internal constant URI = "https://example.invalid/metacade-project.json";
    int256 internal constant ANSWER = 18_250_000_000;

    Deploy internal script;
    // With no key given, vm.startBroadcast() sends from Foundry's default sender, and the
    // script requires the admin to be the broadcaster.
    address internal admin = DEFAULT_SENDER;
    address internal owner = makeAddr("owner");

    function setUp() public {
        script = new Deploy();
        // A deterministic weekday (Wednesday 2026-09-23 12:00 UTC), so VALID is reachable.
        vm.warp(1_790_164_800);
    }

    function _run() internal returns (Deploy.Deployment memory d, uint256 txCount) {
        uint256 before = vm.getNonce(admin);
        d = script.deploy(admin, owner, URI, ANSWER);
        txCount = vm.getNonce(admin) - before;
    }

    function test_Mainnet_DeploysExactlyTheTwoProductionContracts() public {
        vm.chainId(4663);
        (Deploy.Deployment memory d, uint256 txCount) = _run();

        // Two creates, configureAsset, registerProject. No mock, no third contract.
        assertEq(txCount, 4, "mainnet path sends four transactions");
        assertFalse(d.feedIsMock);
        assertEq(d.feed, MAINNET_NVDA_FEED);
        assertEq(d.stockToken, MAINNET_NVDA_TOKEN);

        OracleGuard.AssetConfig memory cfg = d.guard.getAssetConfig("NVDA");
        assertEq(cfg.feed, MAINNET_NVDA_FEED);
        assertEq(cfg.stockToken, MAINNET_NVDA_TOKEN);
        assertTrue(cfg.isEquity);
        assertEq(cfg.maxStaleness, 90_000);
        assertEq(cfg.maxHeldStaleness, 432_000);

        ProjectHomeRegistry.Project memory p = d.registry.getProject(d.projectId);
        assertEq(p.homeChainId, 4663);
        assertEq(p.owner, owner);
        assertEq(p.treasury, address(0), "treasury stays unset");
    }

    function test_Testnet_DeploysMockAndWiresGuardToIt() public {
        vm.chainId(46630);
        (Deploy.Deployment memory d, uint256 txCount) = _run();

        // Mock create, two creates, configureAsset, registerProject.
        assertEq(txCount, 5, "testnet path adds only the mock");
        assertTrue(d.feedIsMock);
        assertTrue(d.feed != MAINNET_NVDA_FEED, "testnet never points at the mainnet proxy");
        assertEq(d.stockToken, address(0));
        assertGt(d.feed.code.length, 0);
        assertEq(MockAggregator(d.feed).decimals(), 8);

        OracleGuard.AssetConfig memory cfg = d.guard.getAssetConfig("NVDA");
        assertEq(cfg.feed, d.feed);
        assertTrue(cfg.isEquity, "market-session path is exercised");

        OracleGuard.PriceStatus memory s = d.guard.checkPrice("NVDA");
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.VALID));
        assertEq(s.answer, ANSWER);
        assertEq(s.updatedAt, block.timestamp, "seeded with the current timestamp");
        assertFalse(s.marketClosed);

        assertEq(d.registry.getProject(d.projectId).homeChainId, 46630);
        assertEq(d.registry.getProject(d.projectId).treasury, address(0));
    }

    function test_Testnet_ClosedSessionAnnotatesTheHeldPrice() public {
        vm.chainId(46630);
        (Deploy.Deployment memory d,) = _run();

        // Saturday 2026-10-03 12:00 UTC, inside the evaluation window.
        vm.warp(1_790_424_000);
        MockAggregator(d.feed).setUpdatedAt(block.timestamp - 1 days);

        OracleGuard.PriceStatus memory s = d.guard.checkPrice("NVDA");
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.VALID));
        assertTrue(s.marketClosed);
    }

    function test_AdminThatIsNotTheBroadcasterRevertsBeforeSending() public {
        vm.chainId(4663);
        address other = makeAddr("other");
        uint256 before = vm.getNonce(admin);
        vm.expectRevert(abi.encodeWithSelector(Deploy.AdminIsNotBroadcaster.selector, other, admin));
        script.deploy(other, owner, URI, ANSWER);
        assertEq(vm.getNonce(admin), before);
    }

    function test_OtherChainsRevertBeforeSendingAnything() public {
        uint256[3] memory chains = [uint256(1), 8453, 421614];
        for (uint256 i = 0; i < chains.length; ++i) {
            vm.chainId(chains[i]);
            uint256 before = vm.getNonce(admin);
            vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, chains[i]));
            script.deploy(admin, owner, URI, ANSWER);
            assertEq(vm.getNonce(admin), before);
        }
    }
}
