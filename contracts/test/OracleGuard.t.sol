// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";

contract OracleGuardTest is Test {
    OracleGuard internal guard;
    MockAggregator internal feed;
    MockAggregator internal sequencer;
    MockStockToken internal token;

    address internal admin = makeAddr("admin");
    address internal stranger = makeAddr("stranger");

    string internal constant SYMBOL = "NVDA";

    // Mirrors the live Robinhood NVDA / USD feed: 8 decimals, 86400s heartbeat.
    uint8 internal constant FEED_DECIMALS = 8;
    uint32 internal constant MAX_STALENESS = 90_000; // heartbeat + 1h buffer
    uint32 internal constant MAX_HELD_STALENESS = 432_000; // 5 days, bounds a long closure
    int256 internal constant PRICE = 21_931_552_275; // 219.31552275 USD at 8 decimals

    // Timestamps chosen so that ((ts / 1 days) + 4) % 7 lands on a known weekday.
    uint256 internal constant WEDNESDAY_NOON = 21_006 * 86_400 + 43_200;
    uint256 internal constant SATURDAY_NOON = 21_002 * 86_400 + 43_200;

    function setUp() public {
        vm.warp(WEDNESDAY_NOON);
        guard = new OracleGuard(admin);
        feed = new MockAggregator(FEED_DECIMALS, PRICE, block.timestamp);
        sequencer = new MockAggregator(0, 0, block.timestamp);
        token = new MockStockToken();

        vm.prank(admin);
        guard.configureAsset(SYMBOL, address(feed), address(token), MAX_STALENESS, MAX_HELD_STALENESS, true);
    }

    function _state(string memory symbol) internal view returns (OracleGuard.OracleState) {
        return guard.checkPrice(symbol).state;
    }

    /// Row 1: valid feed returns VALID.
    function test_ValidFeedReturnsValid() public view {
        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.VALID));
        assertEq(s.answer, PRICE);
        assertEq(s.feedDecimals, FEED_DECIMALS);
        assertEq(s.age, 0);
        assertFalse(s.marketClosed, "Wednesday is an open session");
    }

    /// Row 2: unsupported asset returns UNSUPPORTED.
    function test_UnconfiguredAssetReturnsUnsupported() public view {
        assertEq(uint8(_state("TSLA")), uint8(OracleGuard.OracleState.UNSUPPORTED));
    }

    /// UNSUPPORTED is the zero value, so an uninitialised read can never read as VALID.
    function test_UnsupportedIsTheZeroValue() public pure {
        assertEq(uint8(OracleGuard.OracleState.UNSUPPORTED), 0);
    }

    function test_RemovedAssetReturnsUnsupported() public {
        vm.prank(admin);
        guard.removeAsset(SYMBOL);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.UNSUPPORTED));
        assertEq(guard.assetCount(), 0);
    }

    /// Row 3: zero or negative answer returns INVALID_ANSWER.
    function test_ZeroAnswerReturnsInvalidAnswer() public {
        feed.setAnswer(0);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    function test_NegativeAnswerReturnsInvalidAnswer() public {
        feed.setAnswer(-1);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    /// Row 4: a missing timestamp is not treated as a price.
    function test_MissingTimestampReturnsInvalidAnswer() public {
        feed.setUpdatedAt(0);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    function test_FutureTimestampReturnsInvalidAnswer() public {
        feed.setUpdatedAt(block.timestamp + 1);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    function test_RevertingFeedReturnsInvalidAnswerAndDoesNotBubble() public {
        feed.setShouldRevert(true);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    /// A feed that answers but will not report its scale must not be trusted. Reading a
    /// price against an assumed scale is worse than reporting no price at all.
    function test_FeedThatWillNotReportDecimalsIsInvalidNotValid() public {
        feed.setDecimalsShouldRevert(true);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.INVALID_ANSWER));
        assertEq(s.normalizedAnswer, 0, "no normalised price may be published");
    }

    /// An answer large enough to overflow the scale-up must report a state, not revert.
    function test_OverflowingAnswerReturnsInvalidAnswerAndDoesNotRevert() public {
        feed.setDecimals(0);
        feed.setAnswer(type(int256).max / 2);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    /// An answer that collapses to zero when scaled down is not a price.
    function test_AnswerThatScalesDownToZeroIsInvalid() public {
        feed.setDecimals(30);
        feed.setAnswer(1);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    /// An implausible decimals value is a malfunctioning feed, not a scale.
    function test_ImplausibleDecimalsIsInvalid() public {
        feed.setDecimals(guard.MAX_PLAUSIBLE_DECIMALS() + 1);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.INVALID_ANSWER));
    }

    /// Row 5: stale value returns STALE.
    function test_StalePriceInOpenSessionReturnsStale() public {
        vm.warp(block.timestamp + MAX_STALENESS + 1);
        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.STALE));
        assertFalse(s.marketClosed);
    }

    function test_PriceAtExactlyMaxStalenessIsStillValid() public {
        vm.warp(block.timestamp + MAX_STALENESS);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.VALID));
    }

    /// Row 6: sequencer down returns SEQUENCER_DOWN.
    function test_SequencerDownReturnsSequencerDown() public {
        vm.startPrank(admin);
        guard.setSequencerUptimeFeed(address(sequencer));
        vm.stopPrank();

        sequencer.setAnswer(1);
        sequencer.setStartedAt(block.timestamp - 10 days);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.SEQUENCER_DOWN));
    }

    function test_RevertingSequencerReturnsSequencerDown() public {
        vm.prank(admin);
        guard.setSequencerUptimeFeed(address(sequencer));
        sequencer.setShouldRevert(true);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.SEQUENCER_DOWN));
    }

    /// Row 7: recovery period returns GRACE_PERIOD.
    function test_WithinGracePeriodReturnsGracePeriod() public {
        vm.prank(admin);
        guard.setSequencerUptimeFeed(address(sequencer));

        sequencer.setAnswer(0);
        sequencer.setStartedAt(block.timestamp - (guard.SEQUENCER_GRACE_PERIOD() - 1));
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.GRACE_PERIOD));
    }

    function test_AfterGracePeriodReturnsValid() public {
        vm.prank(admin);
        guard.setSequencerUptimeFeed(address(sequencer));

        sequencer.setAnswer(0);
        sequencer.setStartedAt(block.timestamp - (guard.SEQUENCER_GRACE_PERIOD() + 1));
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.VALID));
    }

    function test_UnsetSequencerRoundReturnsGracePeriod() public {
        vm.prank(admin);
        guard.setSequencerUptimeFeed(address(sequencer));
        sequencer.setAnswer(0);
        sequencer.setStartedAt(0);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.GRACE_PERIOD));
    }

    /// With no sequencer feed configured the sequencer checks are skipped entirely.
    function test_NoSequencerFeedConfiguredSkipsSequencerChecks() public view {
        assertEq(guard.sequencerUptimeFeed(), address(0));
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.VALID));
    }

    /// Row 8: corporate-action pause returns ORACLE_PAUSED.
    function test_PausedOracleReturnsOraclePaused() public {
        token.setPaused(true);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.ORACLE_PAUSED));
    }

    /// Freshness is the primary guard: a paused feed that has also gone stale is STALE.
    function test_StalenessTakesPrecedenceOverPauseFlag() public {
        token.setPaused(true);
        vm.warp(block.timestamp + MAX_STALENESS + 1);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.STALE));
    }

    /// A token that does not expose the advisory interface must not break the read.
    function test_TokenWithoutPauseInterfaceStillReturnsValid() public {
        token.setShouldRevert(true);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.VALID));
    }

    function test_UnsetStockTokenSkipsPauseCheck() public {
        vm.prank(admin);
        guard.configureAsset(SYMBOL, address(feed), address(0), MAX_STALENESS, MAX_HELD_STALENESS, true);
        assertEq(uint8(_state(SYMBOL)), uint8(OracleGuard.OracleState.VALID));
    }

    /// Row 9: a held price during a closed session is VALID, annotated market-closed.
    function test_HeldPriceDuringClosedSessionIsValidAndAnnotated() public {
        vm.warp(SATURDAY_NOON);
        feed.setUpdatedAt(block.timestamp - 2 days); // far past the open-session bound

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertTrue(guard.isMarketClosed(), "Saturday is a closed session");
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.VALID));
        assertTrue(s.marketClosed, "held price must carry the market-closed annotation");
        assertGt(s.age, MAX_STALENESS, "this age would be STALE in an open session");
    }

    /// The same age on an open session is STALE. This is the pair that proves the
    /// two conditions are distinguished rather than collapsed.
    function test_SameAgeIsStaleOnAnOpenSession() public {
        vm.warp(WEDNESDAY_NOON);
        feed.setUpdatedAt(block.timestamp - 2 days);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertFalse(guard.isMarketClosed());
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.STALE));
        assertFalse(s.marketClosed);
    }

    /// The held-price allowance is bounded. Past the ceiling it is STALE even when closed.
    function test_HeldPriceBeyondCeilingIsStaleEvenWhenClosed() public {
        vm.warp(SATURDAY_NOON);
        feed.setUpdatedAt(block.timestamp - (MAX_HELD_STALENESS + 1));

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertTrue(guard.isMarketClosed());
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.STALE));
    }

    /// A non-equity asset gets no market-session allowance.
    function test_NonEquityAssetGetsNoClosedSessionAllowance() public {
        vm.prank(admin);
        guard.configureAsset("ETH", address(feed), address(0), MAX_STALENESS, MAX_HELD_STALENESS, false);

        vm.warp(SATURDAY_NOON);
        feed.setUpdatedAt(block.timestamp - 2 days);

        OracleGuard.PriceStatus memory s = guard.checkPrice("ETH");
        assertEq(uint8(s.state), uint8(OracleGuard.OracleState.STALE));
        assertFalse(s.marketClosed, "crypto trades through the weekend");
    }

    function test_SundayIsAlsoAClosedSession() public {
        vm.warp(SATURDAY_NOON + 1 days);
        assertTrue(guard.isMarketClosed());
    }

    function test_WeekdaysAreOpenSessions() public {
        for (uint256 i = 0; i < 5; ++i) {
            vm.warp(SATURDAY_NOON + (2 + i) * 1 days);
            assertFalse(guard.isMarketClosed(), "Monday through Friday are open");
        }
    }

    /// Row 10: decimal normalisation is correct.
    function test_NormalizationFromEightDecimals() public view {
        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(s.feedDecimals, 8);
        assertEq(s.normalizedAnswer, PRICE * 1e10);
    }

    function test_NormalizationFromEighteenDecimalsIsIdentity() public {
        feed.setDecimals(18);
        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(s.feedDecimals, 18);
        assertEq(s.normalizedAnswer, PRICE);
    }

    function test_NormalizationFromTwentyDecimalsScalesDown() public {
        feed.setDecimals(20);
        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(s.feedDecimals, 20);
        assertEq(s.normalizedAnswer, PRICE / 100);
    }

    function testFuzz_NormalizationRoundTrips(uint8 decimals_, uint96 raw) public {
        decimals_ = uint8(bound(decimals_, 0, 18));
        vm.assume(raw > 0);
        feed.setDecimals(decimals_);
        feed.setAnswer(int256(uint256(raw)));
        feed.setUpdatedAt(block.timestamp);

        OracleGuard.PriceStatus memory s = guard.checkPrice(SYMBOL);
        assertEq(s.normalizedAnswer, int256(uint256(raw)) * int256(10 ** uint256(18 - decimals_)));
    }

    // --- access control ---

    function test_ConfigureAssetRequiresRole() public {
        bytes32 role = guard.ASSET_MANAGER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        guard.configureAsset("X", address(feed), address(0), 1, 1, false);
    }

    function test_SetSequencerFeedRequiresAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, bytes32(0)
            )
        );
        vm.prank(stranger);
        guard.setSequencerUptimeFeed(address(sequencer));
    }

    function test_ConfigureRejectsZeroFeed() public {
        vm.prank(admin);
        vm.expectRevert(OracleGuard.InvalidFeed.selector);
        guard.configureAsset("X", address(0), address(0), 1, 1, false);
    }

    function test_ConfigureRejectsInvalidStaleness() public {
        vm.startPrank(admin);
        vm.expectRevert(OracleGuard.InvalidStaleness.selector);
        guard.configureAsset("X", address(feed), address(0), 0, 1, false);

        vm.expectRevert(OracleGuard.InvalidStaleness.selector);
        guard.configureAsset("X", address(feed), address(0), 100, 99, false);
        vm.stopPrank();
    }

    function test_ConfigureRejectsEmptySymbol() public {
        vm.prank(admin);
        vm.expectRevert(OracleGuard.EmptySymbol.selector);
        guard.configureAsset("", address(feed), address(0), 1, 1, false);
    }

    function test_ZeroAdminInConstructorReverts() public {
        vm.expectRevert(OracleGuard.InvalidAdmin.selector);
        new OracleGuard(address(0));
    }

    function test_GuardRejectsEther() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool sent,) = address(guard).call{value: 1 ether}("");
        assertFalse(sent, "guard must not accept value");
    }
}
