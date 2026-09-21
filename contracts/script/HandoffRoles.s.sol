// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProjectHomeRegistry} from "../src/ProjectHomeRegistry.sol";
import {OracleGuard} from "../src/OracleGuard.sol";

/// @notice Moves every role on the deployed pair from the deployer to a new admin, then
///         removes the deployer.
/// @dev    Run by the deployer straight after Deploy.s.sol. Ten transactions: five grants,
///         then five renounces, with DEFAULT_ADMIN_ROLE renounced last on each contract so
///         the deployer never holds a lesser role without the admin role above it.
///
///         NEW_ADMIN is a required input with no default. The script refuses to run when
///         it is unset, zero, or the deployer itself, and it checks the end state inside
///         the same run: the deployer holds none of the five roles and the new admin holds
///         all five. It also requires the project owner to already be the new admin,
///         which Deploy.s.sol does when run with PROJECT_OWNER set to the same address;
///         the registry has no way to change a project owner after registration.
contract HandoffRoles is Script {
    uint256 internal constant MAINNET_CHAIN_ID = 4663;
    uint256 internal constant TESTNET_CHAIN_ID = 46630;
    string internal constant PROJECT_SLUG = "metacade";

    struct Grant {
        address target;
        bytes32 role;
        string label;
    }

    error UnsupportedChain(uint256 chainId);
    error InvalidNewAdmin(address newAdmin);
    error NoCode(address target);
    error BroadcasterLacksRole(string label);
    error ProjectOwnerIsNotNewAdmin(address owner, address newAdmin);
    error HandoffIncomplete(string label, address account, bool expected);

    function run() external {
        handoff(
            ProjectHomeRegistry(vm.envAddress("REGISTRY_ADDRESS")),
            OracleGuard(vm.envAddress("ORACLE_GUARD_ADDRESS")),
            vm.envAddress("NEW_ADMIN")
        );
    }

    function roles(ProjectHomeRegistry registry, OracleGuard guard) public view returns (Grant[5] memory g) {
        g[0] = Grant(address(registry), registry.REGISTRAR_ROLE(), "ProjectHomeRegistry.REGISTRAR_ROLE");
        g[1] = Grant(address(registry), registry.CURATOR_ROLE(), "ProjectHomeRegistry.CURATOR_ROLE");
        g[2] =
            Grant(address(registry), registry.DEFAULT_ADMIN_ROLE(), "ProjectHomeRegistry.DEFAULT_ADMIN_ROLE");
        g[3] = Grant(address(guard), guard.ASSET_MANAGER_ROLE(), "OracleGuard.ASSET_MANAGER_ROLE");
        g[4] = Grant(address(guard), guard.DEFAULT_ADMIN_ROLE(), "OracleGuard.DEFAULT_ADMIN_ROLE");
    }

    function handoff(ProjectHomeRegistry registry, OracleGuard guard, address newAdmin) public {
        if (block.chainid != MAINNET_CHAIN_ID && block.chainid != TESTNET_CHAIN_ID) {
            revert UnsupportedChain(block.chainid);
        }
        if (address(registry).code.length == 0) revert NoCode(address(registry));
        if (address(guard).code.length == 0) revert NoCode(address(guard));

        // Identify the broadcasting account, then close the broadcast so that every check
        // below runs before a single transaction is queued.
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        vm.stopBroadcast();

        if (newAdmin == address(0) || newAdmin == deployer) revert InvalidNewAdmin(newAdmin);

        address owner = registry.getProjectBySlug(PROJECT_SLUG).owner;
        if (owner != newAdmin) revert ProjectOwnerIsNotNewAdmin(owner, newAdmin);

        Grant[5] memory g = roles(registry, guard);
        for (uint256 i = 0; i < g.length; ++i) {
            if (!_has(g[i], deployer)) revert BroadcasterLacksRole(g[i].label);
        }

        vm.startBroadcast();
        // Grants first, so the new admin holds everything before the deployer lets go.
        for (uint256 i = 0; i < g.length; ++i) {
            ProjectHomeRegistry(g[i].target).grantRole(g[i].role, newAdmin);
        }
        // Renounces in list order: lesser roles, then DEFAULT_ADMIN_ROLE, per contract.
        for (uint256 i = 0; i < g.length; ++i) {
            ProjectHomeRegistry(g[i].target).renounceRole(g[i].role, deployer);
        }

        vm.stopBroadcast();

        for (uint256 i = 0; i < g.length; ++i) {
            if (_has(g[i], deployer)) revert HandoffIncomplete(g[i].label, deployer, false);
            if (!_has(g[i], newAdmin)) revert HandoffIncomplete(g[i].label, newAdmin, true);
            console2.log(g[i].label);
            console2.log("  deployer ", deployer, _has(g[i], deployer));
            console2.log("  newAdmin ", newAdmin, _has(g[i], newAdmin));
        }
    }

    /// @dev Both contracts inherit OpenZeppelin AccessControl, so one interface reads both.
    function _has(Grant memory g, address account) internal view returns (bool) {
        return ProjectHomeRegistry(g.target).hasRole(g.role, account);
    }
}
