// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProjectHomeRegistry} from "../src/ProjectHomeRegistry.sol";
import {OracleGuard} from "../src/OracleGuard.sol";
import {MockAggregator} from "../test/mocks/MockAggregator.sol";

/// @notice Deploys the Arena Project Home reference pair and seeds it.
/// @dev    Configuration is selected by block.chainid, so the same script runs on the
///         testnet rehearsal and on mainnet without editing constants by hand.
///
///         4663  Robinhood Chain Mainnet. Two contracts, no more. The guard points at
///               the official Chainlink proxy and the official Robinhood Stock Token.
///         46630 Robinhood Chain Testnet. Chainlink publishes no Robinhood feed here,
///               so the script first deploys a MockAggregator as test scaffolding and
///               points the guard at it. This proves the deploy, access control and
///               verification mechanics only; it is never a price source.
///         Any other chain reverts.
///
///         Run without --broadcast to simulate and produce gas estimates. Broadcasting
///         on mainnet spends gas and is gated on explicit approval.
contract Deploy is Script {
    uint256 internal constant MAINNET_CHAIN_ID = 4663;
    uint256 internal constant TESTNET_CHAIN_ID = 46630;

    // Official Chainlink Data Feeds directory, Robinhood Chain mainnet, Robinhood NVDA / USD.
    address internal constant MAINNET_NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    // Official Robinhood asset registry (api.robinhood.com/rhj/assets), NVDA on chainId 4663.
    address internal constant MAINNET_NVDA_TOKEN = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    // Testnet scaffolding. Matches the official feed's 8 decimals. The seed answer is
    // overridable with MOCK_NVDA_ANSWER so the rehearsal can carry a current price.
    uint8 internal constant MOCK_DECIMALS = 8;
    int256 internal constant MOCK_DEFAULT_ANSWER = 180e8;

    // Feed heartbeat is 86400s. The open-session bound adds one hour of headroom.
    uint32 internal constant MAX_STALENESS = 90_000;
    // Bounds a held price across a weekend or a long holiday closure.
    uint32 internal constant MAX_HELD_STALENESS = 432_000;

    string internal constant PROJECT_SLUG = "metacade";
    string internal constant PROJECT_NAME = "Metacade";

    struct NetworkConfig {
        address feed;
        address stockToken;
        bool feedIsMock;
    }

    struct Deployment {
        ProjectHomeRegistry registry;
        OracleGuard guard;
        address feed;
        address stockToken;
        bool feedIsMock;
        uint256 projectId;
    }

    error UnsupportedChain(uint256 chainId);
    error AdminIsNotBroadcaster(address admin, address broadcaster);

    function run() external returns (Deployment memory d) {
        address admin = vm.envAddress("DEPLOY_ADMIN");
        address projectOwner = vm.envOr("PROJECT_OWNER", admin);
        string memory metadataURI = vm.envOr(
            "PROJECT_METADATA_URI",
            string(
                "https://raw.githubusercontent.com/metacade-labs/arena-project-home/main/deployments/metacade-project.json"
            )
        );
        int256 mockAnswer = vm.envOr("MOCK_NVDA_ANSWER", MOCK_DEFAULT_ANSWER);

        d = deploy(admin, projectOwner, metadataURI, mockAnswer);

        console2.log("chainId            ", block.chainid);
        console2.log("ProjectHomeRegistry", address(d.registry));
        console2.log("OracleGuard        ", address(d.guard));
        console2.log("feed               ", d.feed);
        console2.log("feed is mock       ", d.feedIsMock);
        console2.log("stockToken         ", d.stockToken);
        console2.log("projectId          ", d.projectId);
        console2.log("admin              ", admin);
        console2.log("sequencer feed     ", d.guard.sequencerUptimeFeed());
    }

    function deploy(address admin, address projectOwner, string memory metadataURI, int256 mockAnswer)
        public
        returns (Deployment memory d)
    {
        // Selected before any broadcast so an unsupported chain sends nothing.
        if (block.chainid != MAINNET_CHAIN_ID && block.chainid != TESTNET_CHAIN_ID) {
            revert UnsupportedChain(block.chainid);
        }

        vm.startBroadcast();

        // configureAsset and registerProject are role-gated to the admin, so the admin
        // must be the account that broadcasts. Fail here with a clear message rather
        // than partway through the sequence.
        (, address broadcaster,) = vm.readCallers();
        if (broadcaster != admin) revert AdminIsNotBroadcaster(admin, broadcaster);

        NetworkConfig memory cfg = _networkConfig(mockAnswer);

        d.registry = new ProjectHomeRegistry(admin);
        d.guard = new OracleGuard(admin);

        d.guard.configureAsset("NVDA", cfg.feed, cfg.stockToken, MAX_STALENESS, MAX_HELD_STALENESS, true);

        d.projectId =
            d.registry.registerProject(PROJECT_SLUG, PROJECT_NAME, projectOwner, metadataURI, block.chainid);

        vm.stopBroadcast();

        d.feed = cfg.feed;
        d.stockToken = cfg.stockToken;
        d.feedIsMock = cfg.feedIsMock;

        // Treasury is deliberately left unset. It renders as NOT CONFIGURED.
        require(d.registry.getProject(d.projectId).treasury == address(0), "treasury must start unset");
    }

    /// @dev Must be called inside the broadcast: on testnet it deploys the mock.
    function _networkConfig(int256 mockAnswer) internal returns (NetworkConfig memory) {
        if (block.chainid == MAINNET_CHAIN_ID) {
            return NetworkConfig({feed: MAINNET_NVDA_FEED, stockToken: MAINNET_NVDA_TOKEN, feedIsMock: false});
        }
        // TESTNET_CHAIN_ID. The only other chain deploy() lets through.
        // No Stock Token exists on testnet, so the pause flag is recorded as unavailable.
        MockAggregator mock = new MockAggregator(MOCK_DECIMALS, mockAnswer, block.timestamp);
        return NetworkConfig({feed: address(mock), stockToken: address(0), feedIsMock: true});
    }
}
