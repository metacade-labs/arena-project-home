// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProjectHomeRegistry} from "../src/ProjectHomeRegistry.sol";
import {OracleGuard} from "../src/OracleGuard.sol";

/// @notice Deploys the Arena Project Home reference pair and seeds it.
/// @dev    Two contracts are deployed and no more. Run without --broadcast to
///         simulate and produce gas estimates; broadcasting spends mainnet gas and
///         is gated on explicit approval.
contract Deploy is Script {
    // Official Chainlink Data Feeds directory, Robinhood Chain mainnet.
    address internal constant NVDA_FEED = 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15;
    // Official Robinhood asset registry, NVDA on chainId 4663.
    address internal constant NVDA_TOKEN = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;

    // Feed heartbeat is 86400s. The open-session bound adds one hour of headroom.
    uint32 internal constant MAX_STALENESS = 90_000;
    // Bounds a held price across a weekend or a long holiday closure.
    uint32 internal constant MAX_HELD_STALENESS = 432_000;

    string internal constant PROJECT_SLUG = "metacade";
    string internal constant PROJECT_NAME = "Metacade";

    function run() external {
        address admin = vm.envAddress("DEPLOY_ADMIN");
        address projectOwner = vm.envOr("PROJECT_OWNER", admin);
        string memory metadataURI = vm.envOr(
            "PROJECT_METADATA_URI",
            string(
                "https://raw.githubusercontent.com/metacade-labs/arena-project-home/main/deployments/metacade-project.json"
            )
        );

        vm.startBroadcast();

        ProjectHomeRegistry registry = new ProjectHomeRegistry(admin);
        OracleGuard guard = new OracleGuard(admin);

        guard.configureAsset("NVDA", NVDA_FEED, NVDA_TOKEN, MAX_STALENESS, MAX_HELD_STALENESS, true);

        uint256 projectId = registry.registerProject(
            PROJECT_SLUG, PROJECT_NAME, projectOwner, metadataURI, ROBINHOOD_CHAIN_ID
        );

        vm.stopBroadcast();

        // Treasury is deliberately left unset. It renders as NOT CONFIGURED.
        require(registry.getProject(projectId).treasury == address(0), "treasury must start unset");

        console2.log("chainId            ", block.chainid);
        console2.log("ProjectHomeRegistry", address(registry));
        console2.log("OracleGuard        ", address(guard));
        console2.log("projectId          ", projectId);
        console2.log("admin              ", admin);
        console2.log("sequencer feed     ", guard.sequencerUptimeFeed());
    }
}
