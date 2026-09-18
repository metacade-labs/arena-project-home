// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IStockToken} from "../src/OracleGuard.sol";

/// @notice Live-feed proof against Robinhood Chain mainnet.
/// @dev    Skipped unless ROBINHOOD_RPC_URL is set, so CI stays green without an RPC.
///         Addresses are read from the official Chainlink directory and the official
///         Robinhood asset API; none are inferred.
contract OracleGuardForkTest is Test {
    // Chainlink Data Feeds directory, Robinhood Chain mainnet, Robinhood NVDA / USD.
    address internal constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    // Robinhood asset registry (api.robinhood.com/rhj/assets), NVDA on chainId 4663.
    address internal constant NVDA_TOKEN = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;

    uint32 internal constant MAX_STALENESS = 90_000;
    uint32 internal constant MAX_HELD_STALENESS = 432_000;

    OracleGuard internal guard;
    address internal admin = makeAddr("admin");
    bool internal forked;

    function setUp() public {
        string memory rpc = vm.envOr("ROBINHOOD_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;

        guard = new OracleGuard(admin);
        vm.prank(admin);
        guard.configureAsset("NVDA", NVDA_FEED, NVDA_TOKEN, MAX_STALENESS, MAX_HELD_STALENESS, true);
    }

    function test_Fork_ChainIdIsRobinhoodMainnet() public view {
        if (!forked) return;
        assertEq(block.chainid, ROBINHOOD_CHAIN_ID);
    }

    /// The feed's own reported parameters must match the official directory.
    function test_Fork_FeedMatchesOfficialDirectory() public view {
        if (!forked) return;
        AggregatorV3Interface feed = AggregatorV3Interface(NVDA_FEED);
        assertEq(feed.decimals(), 8, "official directory: 8 decimals");
        assertEq(feed.version(), 6, "official directory: aggregator version 6");
        assertEq(feed.description(), "RHNVDA / USD");
    }

    /// The pause interface exists on the token, not on the feed proxy.
    function test_Fork_StockTokenExposesPauseInterface() public view {
        if (!forked) return;
        // A successful call is the assertion; a token without the interface would revert.
        IStockToken(NVDA_TOKEN).oraclePaused();
    }

    /// The live read must land on a state the frontend knows how to render, and must
    /// never be UNSUPPORTED for a configured asset.
    function test_Fork_LiveReadReturnsARenderableState() public {
        if (!forked) return;
        OracleGuard.PriceStatus memory s = guard.checkPrice("NVDA");

        assertTrue(
            s.state != OracleGuard.OracleState.UNSUPPORTED, "configured asset must not read UNSUPPORTED"
        );
        assertEq(s.feedDecimals, 8, "decimals read from the feed");

        if (s.state == OracleGuard.OracleState.VALID) {
            assertGt(s.answer, 0);
            assertEq(s.normalizedAnswer, s.answer * 1e10);
            assertEq(s.marketClosed, guard.isMarketClosed());
        }

        emit log_named_uint("state", uint8(s.state));
        emit log_named_int("answer (8dp)", s.answer);
        emit log_named_uint("age seconds", s.age);
        emit log_named_string("market closed", s.marketClosed ? "true" : "false");
    }
}
