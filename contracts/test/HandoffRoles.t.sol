// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {HandoffRoles} from "../script/HandoffRoles.s.sol";

/// @notice Runs Deploy.s.sol and then HandoffRoles.s.sol as the same broadcaster, the way
///         they run on mainnet, and asserts the end state of all five roles.
contract HandoffRolesTest is Test {
    string internal constant URI = "https://example.invalid/metacade-project.json";

    Deploy internal deployScript;
    HandoffRoles internal handoffScript;
    address internal deployer = DEFAULT_SENDER;
    address internal newAdmin = makeAddr("newAdmin");
    Deploy.Deployment internal d;

    function setUp() public {
        vm.chainId(4663);
        deployScript = new Deploy();
        handoffScript = new HandoffRoles();
        d = deployScript.deploy(deployer, newAdmin, URI, 0);
    }

    function _assertRoles(address account, bool expected) internal view {
        HandoffRoles.Grant[5] memory g = handoffScript.roles(d.registry, d.guard);
        for (uint256 i = 0; i < g.length; ++i) {
            bool has = d.registry.hasRole(g[i].role, account);
            if (g[i].target == address(d.guard)) has = d.guard.hasRole(g[i].role, account);
            assertEq(has, expected, g[i].label);
        }
    }

    function test_HandoffMovesAllFiveRolesAndRemovesDeployer() public {
        _assertRoles(deployer, true);
        _assertRoles(newAdmin, false);

        uint256 before = vm.getNonce(deployer);
        handoffScript.handoff(d.registry, d.guard, newAdmin);

        assertEq(vm.getNonce(deployer) - before, 10, "five grants and five renounces");
        _assertRoles(deployer, false);
        _assertRoles(newAdmin, true);
    }

    function test_NewAdminCanActAndDeployerCannot() public {
        handoffScript.handoff(d.registry, d.guard, newAdmin);

        vm.prank(newAdmin);
        d.registry.setProjectActive(d.projectId, false);
        vm.prank(newAdmin);
        d.guard.setSequencerUptimeFeed(address(0));

        vm.expectRevert();
        vm.prank(deployer);
        d.registry.setProjectActive(d.projectId, true);
        vm.expectRevert();
        vm.prank(deployer);
        d.guard.configureAsset("NVDA", address(1), address(0), 1, 1, true);
    }

    function test_RefusesZeroOrDeployerAsNewAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(HandoffRoles.InvalidNewAdmin.selector, address(0)));
        handoffScript.handoff(d.registry, d.guard, address(0));

        vm.expectRevert(abi.encodeWithSelector(HandoffRoles.InvalidNewAdmin.selector, deployer));
        handoffScript.handoff(d.registry, d.guard, deployer);
        _assertRoles(deployer, true);
    }

    function test_RefusesWhenProjectOwnerIsNotTheNewAdmin() public {
        address other = makeAddr("other");
        vm.expectRevert(
            abi.encodeWithSelector(HandoffRoles.ProjectOwnerIsNotNewAdmin.selector, newAdmin, other)
        );
        handoffScript.handoff(d.registry, d.guard, other);
        _assertRoles(deployer, true);
    }

    function test_RefusesOnOtherChains() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(HandoffRoles.UnsupportedChain.selector, 1));
        handoffScript.handoff(d.registry, d.guard, newAdmin);
    }
}
