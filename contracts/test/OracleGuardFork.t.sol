// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IStockToken} from "../src/OracleGuard.sol";

/// @notice The proxy's pointer to its current underlying aggregator.
interface IAggregatorProxy {
    function aggregator() external view returns (address);
}

/// @notice Live-feed proof against Robinhood Chain mainnet.
/// @dev    Skipped unless ROBINHOOD_RPC_URL is set. The skip is a real vm.skip, so an
///         unset RPC shows as "skipped" in the summary rather than as a silent pass.
///         Addresses are read from the official Chainlink directory and the official
///         Robinhood asset API; none are inferred.
contract OracleGuardForkTest is Test {
    // Chainlink Data Feeds directory, Robinhood Chain mainnet, Robinhood NVDA / USD.
    address internal constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    // The aggregator the proxy currently points at, per the same directory entry.
    address internal constant NVDA_AGGREGATOR = 0xC9d16E4f2569b9E3ea0468fD85844953713DC2a2;
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

    function test_Fork_ChainIdIsRobinhoodMainnet() public {
        vm.skip(!forked);
        assertEq(block.chainid, ROBINHOOD_CHAIN_ID);
    }

    /// The feed's own reported parameters must match the official directory.
    function test_Fork_FeedMatchesOfficialDirectory() public {
        vm.skip(!forked);
        AggregatorV3Interface feed = AggregatorV3Interface(NVDA_FEED);
        assertEq(feed.decimals(), 8, "official directory: 8 decimals");
        assertEq(feed.version(), 6, "official directory: aggregator version 6");
        assertEq(feed.description(), "RHNVDA / USD");
        assertEq(IAggregatorProxy(NVDA_FEED).aggregator(), NVDA_AGGREGATOR, "aggregator behind the proxy");
    }

    /// The pause interface exists on the token, not on the feed proxy.
    function test_Fork_StockTokenExposesPauseInterface() public {
        vm.skip(!forked);
        // The call must succeed and return a decodable bool. A token without the
        // interface reverts on the extcodesize/selector check.
        bool paused = IStockToken(NVDA_TOKEN).oraclePaused();
        assertTrue(paused == true || paused == false, "oraclePaused must decode as a bool");
    }

    /// The live read must land on a state the frontend knows how to render, and must
    /// never be UNSUPPORTED for a configured asset.
    function test_Fork_LiveReadReturnsARenderableState() public {
        vm.skip(!forked);
        OracleGuard.PriceStatus memory s = guard.checkPrice("NVDA");

        assertTrue(
            s.state != OracleGuard.OracleState.UNSUPPORTED, "configured asset must not read UNSUPPORTED"
        );

        // feedDecimals is only populated once the feed has answered, so assert it on the
        // branches that populate it rather than turning a feed hiccup into a red test.
        if (s.state != OracleGuard.OracleState.INVALID_ANSWER) {
            assertEq(s.feedDecimals, 8, "decimals read from the feed");
        }

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
