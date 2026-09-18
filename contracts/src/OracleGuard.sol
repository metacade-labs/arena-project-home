// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Minimal view of a Robinhood Stock Token. The corporate-action pause
///         flag lives on the token contract, not on the Chainlink proxy.
interface IStockToken {
    function oraclePaused() external view returns (bool);
}

/// @title OracleGuard
/// @notice Returns an explicit validity state for one official Chainlink feed
///         rather than a bare price. Callers are expected to branch on the state.
/// @dev    This contract reads. It holds no value, converts nothing, and has no
///         fallback price source. If the official feed cannot be trusted the
///         answer is a state, never a substitute number.
contract OracleGuard is AccessControl {
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    /// @notice Validity states.
    /// @dev    UNSUPPORTED is deliberately the zero value so that any unset or
    ///         uninitialised read degrades to "not supported" rather than to VALID.
    ///         An unset round (updatedAt == 0) is folded into INVALID_ANSWER; there
    ///         is no separate eighth state. Both choices are recorded in
    ///         docs/architecture.md.
    enum OracleState {
        UNSUPPORTED,
        VALID,
        STALE,
        SEQUENCER_DOWN,
        GRACE_PERIOD,
        ORACLE_PAUSED,
        INVALID_ANSWER
    }

    /// @notice Normalisation target for cross-asset comparison.
    uint8 public constant NORMALIZED_DECIMALS = 18;

    /// @notice Upper bound on a believable feed decimals value.
    /// @dev    Guards the exponent in _normalize. Chainlink feeds are 8 or 18; anything
    ///         above this is a malfunctioning or hostile feed, not a scale.
    uint8 public constant MAX_PLAUSIBLE_DECIMALS = 36;

    /// @notice Grace period applied after the sequencer is observed to come back up.
    /// @dev    CHOSEN VALUE, NOT AN OFFICIAL ROBINHOOD CHAIN PARAMETER. It matches the
    ///         value used in Chainlink's own L2 sequencer example. Robinhood Chain
    ///         publishes no grace period, and at the time of writing publishes no
    ///         sequencer uptime feed at all. See docs/architecture.md.
    uint256 public constant SEQUENCER_GRACE_PERIOD = 3600;

    struct AssetConfig {
        address feed; // Chainlink proxy, official directory only
        address stockToken; // exposes oraclePaused(); address(0) = interface unavailable
        uint32 maxStaleness; // freshness bound while the session is open
        uint32 maxHeldStaleness; // absolute ceiling, applies even when the market is closed
        bool isEquity; // subject to market-session gating
        bool configured;
        string symbol;
    }

    struct PriceStatus {
        OracleState state;
        int256 answer; // raw, in feed decimals
        int256 normalizedAnswer; // scaled to NORMALIZED_DECIMALS
        uint8 feedDecimals; // read from the feed, never assumed
        uint256 updatedAt;
        uint256 age;
        bool marketClosed; // annotation: a held price during a closed session
    }

    /// @notice Sequencer uptime feed. address(0) means no such feed is published
    ///         for this network, in which case the sequencer checks are skipped.
    address public sequencerUptimeFeed;

    mapping(bytes32 => AssetConfig) private _assets;
    bytes32[] private _assetKeys;

    event AssetConfigured(
        bytes32 indexed key, string symbol, address indexed feed, address indexed stockToken
    );
    event AssetRemoved(bytes32 indexed key, string symbol);
    event SequencerUptimeFeedUpdated(address indexed previousFeed, address indexed newFeed);

    error InvalidAdmin();
    error InvalidFeed();
    error InvalidStaleness();
    error EmptySymbol();
    error AssetNotConfigured(string symbol);

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ASSET_MANAGER_ROLE, admin);
    }

    /// @notice Derive the storage key for a symbol.
    function assetKey(string memory symbol) public pure returns (bytes32) {
        return keccak256(bytes(symbol));
    }

    function configureAsset(
        string calldata symbol,
        address feed,
        address stockToken,
        uint32 maxStaleness,
        uint32 maxHeldStaleness,
        bool isEquity
    ) external onlyRole(ASSET_MANAGER_ROLE) {
        if (bytes(symbol).length == 0) revert EmptySymbol();
        if (feed == address(0)) revert InvalidFeed();
        if (maxStaleness == 0 || maxHeldStaleness < maxStaleness) revert InvalidStaleness();

        bytes32 key = assetKey(symbol);
        if (!_assets[key].configured) _assetKeys.push(key);

        _assets[key] = AssetConfig({
            feed: feed,
            stockToken: stockToken,
            maxStaleness: maxStaleness,
            maxHeldStaleness: maxHeldStaleness,
            isEquity: isEquity,
            configured: true,
            symbol: symbol
        });

        emit AssetConfigured(key, symbol, feed, stockToken);
    }

    function removeAsset(string calldata symbol) external onlyRole(ASSET_MANAGER_ROLE) {
        bytes32 key = assetKey(symbol);
        if (!_assets[key].configured) revert AssetNotConfigured(symbol);
        delete _assets[key];

        uint256 n = _assetKeys.length;
        for (uint256 i = 0; i < n; ++i) {
            if (_assetKeys[i] == key) {
                _assetKeys[i] = _assetKeys[n - 1];
                _assetKeys.pop();
                break;
            }
        }
        emit AssetRemoved(key, symbol);
    }

    function setSequencerUptimeFeed(address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address previous = sequencerUptimeFeed;
        sequencerUptimeFeed = feed;
        emit SequencerUptimeFeedUpdated(previous, feed);
    }

    function getAssetConfig(string calldata symbol) external view returns (AssetConfig memory) {
        return _assets[assetKey(symbol)];
    }

    function assetCount() external view returns (uint256) {
        return _assetKeys.length;
    }

    function assetKeyAt(uint256 index) external view returns (bytes32) {
        return _assetKeys[index];
    }

    /// @notice Full validity report for one configured asset.
    /// @dev    Never reverts on a misbehaving feed. A feed that reverts, returns a
    ///         non-positive answer or an unset round reports INVALID_ANSWER.
    function checkPrice(string calldata symbol) external view returns (PriceStatus memory status) {
        return _checkPrice(_assets[assetKey(symbol)]);
    }

    function checkPriceByKey(bytes32 key) external view returns (PriceStatus memory status) {
        return _checkPrice(_assets[key]);
    }

    /// @notice True when the current UTC timestamp falls in the weekly closure of a
    ///         24/5 US-equity session.
    /// @dev    Weekend only. Exchange holidays are not derivable onchain and are not
    ///         modelled; the maxHeldStaleness ceiling is what bounds a long closure.
    ///         See docs/limitations.md.
    function isMarketClosed() public view returns (bool) {
        uint256 dayOfWeek = ((block.timestamp / 1 days) + 4) % 7; // 0 = Sunday
        return dayOfWeek == 0 || dayOfWeek == 6;
    }

    function _checkPrice(AssetConfig storage cfg) private view returns (PriceStatus memory status) {
        if (!cfg.configured) {
            status.state = OracleState.UNSUPPORTED;
            return status;
        }

        // 1. Sequencer, where such a feed exists on this network.
        if (sequencerUptimeFeed != address(0)) {
            (bool ok, int256 seqAnswer, uint256 startedAt) = _readSequencer();
            if (!ok) {
                status.state = OracleState.SEQUENCER_DOWN;
                return status;
            }
            if (seqAnswer != 0) {
                status.state = OracleState.SEQUENCER_DOWN;
                return status;
            }
            if (startedAt == 0 || block.timestamp - startedAt <= SEQUENCER_GRACE_PERIOD) {
                status.state = OracleState.GRACE_PERIOD;
                return status;
            }
        }

        // 2. The feed itself. Decimals are part of the answer, not a detail: a price
        //    read against the wrong scale is worse than no price, so a feed that will
        //    not tell us its decimals is treated as not having answered.
        (bool read, int256 answer, uint256 updatedAt) = _readFeed(cfg.feed);
        (bool decimalsRead, uint8 feedDecimals) = _readDecimals(cfg.feed);
        if (!read || !decimalsRead || answer <= 0 || updatedAt == 0 || updatedAt > block.timestamp) {
            status.state = OracleState.INVALID_ANSWER;
            status.answer = answer;
            status.updatedAt = updatedAt;
            return status;
        }

        (bool scaled, int256 normalized) = _normalize(answer, feedDecimals);
        if (!scaled) {
            status.state = OracleState.INVALID_ANSWER;
            status.answer = answer;
            status.updatedAt = updatedAt;
            status.feedDecimals = feedDecimals;
            return status;
        }

        status.answer = answer;
        status.updatedAt = updatedAt;
        status.age = block.timestamp - updatedAt;
        status.feedDecimals = feedDecimals;
        status.normalizedAnswer = normalized;
        status.marketClosed = cfg.isEquity && isMarketClosed();

        // 3. Freshness is the primary guard and is evaluated before the advisory
        //    pause flag, so a paused feed that has also gone stale reports STALE.
        uint256 bound = status.marketClosed ? cfg.maxHeldStaleness : cfg.maxStaleness;
        if (status.age > bound) {
            status.state = OracleState.STALE;
            return status;
        }

        // 4. Corporate-action pause. Advisory: the token may still return a price.
        if (cfg.stockToken != address(0) && _readPaused(cfg.stockToken)) {
            status.state = OracleState.ORACLE_PAUSED;
            return status;
        }

        status.state = OracleState.VALID;
    }

    function _readSequencer() private view returns (bool ok, int256 answer, uint256 startedAt) {
        try AggregatorV3Interface(sequencerUptimeFeed).latestRoundData() returns (
            uint80, int256 a, uint256 s, uint256, uint80
        ) {
            return (true, a, s);
        } catch {
            return (false, 0, 0);
        }
    }

    function _readFeed(address feed) private view returns (bool ok, int256 answer, uint256 updatedAt) {
        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80, int256 a, uint256, uint256 u, uint80
        ) {
            return (true, a, u);
        } catch {
            return (false, 0, 0);
        }
    }

    function _readDecimals(address feed) private view returns (bool ok, uint8 decimals_) {
        try AggregatorV3Interface(feed).decimals() returns (uint8 d) {
            return (true, d);
        } catch {
            return (false, 0);
        }
    }

    function _readPaused(address token) private view returns (bool) {
        try IStockToken(token).oraclePaused() returns (bool paused) {
            return paused;
        } catch {
            return false;
        }
    }

    /// @notice Scale a positive answer to NORMALIZED_DECIMALS.
    /// @dev    Returns ok = false rather than reverting, so that checkPrice can keep its
    ///         promise never to revert on a misbehaving feed. Three cases fail:
    ///         an implausible decimals value, an answer large enough that scaling up
    ///         would overflow, and an answer small enough that scaling down collapses it
    ///         to zero. Each is out of band and is reported as INVALID_ANSWER.
    function _normalize(int256 answer, uint8 feedDecimals) private pure returns (bool ok, int256) {
        if (feedDecimals > MAX_PLAUSIBLE_DECIMALS) return (false, 0);
        if (feedDecimals == NORMALIZED_DECIMALS) return (true, answer);

        if (feedDecimals < NORMALIZED_DECIMALS) {
            int256 factor = int256(10 ** uint256(NORMALIZED_DECIMALS - feedDecimals));
            if (answer > type(int256).max / factor) return (false, 0);
            return (true, answer * factor);
        }

        int256 scaled = answer / int256(10 ** uint256(feedDecimals - NORMALIZED_DECIMALS));
        if (scaled == 0) return (false, 0);
        return (true, scaled);
    }
}
