// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ProjectHomeRegistry} from "../src/ProjectHomeRegistry.sol";

contract ProjectHomeRegistryTest is Test {
    ProjectHomeRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("projectOwner");
    address internal stranger = makeAddr("stranger");
    address internal safe = makeAddr("safe");

    uint256 internal constant HOME_CHAIN_ID = 4663;

    event ProjectRegistered(
        uint256 indexed id, string slug, string displayName, address indexed owner, uint256 homeChainId
    );
    event ProjectUpdated(uint256 indexed id, string displayName, string metadataURI, address indexed by);
    event TreasuryUpdated(uint256 indexed id, address indexed previousTreasury, address indexed newTreasury);
    event ProjectStatusChanged(uint256 indexed id, bool active, address indexed by);

    function setUp() public {
        registry = new ProjectHomeRegistry(admin);
    }

    function _register() internal returns (uint256 id) {
        vm.prank(admin);
        id = registry.registerProject("metacade", "Metacade", owner, "ipfs://metacade-home", HOME_CHAIN_ID);
    }

    /// Row 1: authorized registration succeeds.
    function test_AuthorizedRegistrationSucceeds() public {
        vm.expectEmit(true, true, false, true);
        emit ProjectRegistered(1, "metacade", "Metacade", owner, HOME_CHAIN_ID);

        uint256 id = _register();

        ProjectHomeRegistry.Project memory p = registry.getProject(id);
        assertEq(id, 1);
        assertEq(p.slug, "metacade");
        assertEq(p.displayName, "Metacade");
        assertEq(p.owner, owner);
        assertEq(p.metadataURI, "ipfs://metacade-home");
        assertEq(p.homeChainId, HOME_CHAIN_ID);
        assertTrue(p.active);
        assertEq(registry.totalProjects(), 1);
        assertTrue(registry.slugTaken("metacade"));
    }

    /// Row 2: unauthorized registration fails.
    function test_UnauthorizedRegistrationReverts() public {
        bytes32 role = registry.REGISTRAR_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        registry.registerProject("metacade", "Metacade", owner, "ipfs://x", HOME_CHAIN_ID);
    }

    /// Row 3: duplicate slug fails.
    function test_DuplicateSlugReverts() public {
        _register();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ProjectHomeRegistry.SlugAlreadyRegistered.selector, "metacade")
        );
        registry.registerProject("metacade", "Different Name", owner, "ipfs://y", HOME_CHAIN_ID);
    }

    /// Row 4: owner update succeeds.
    function test_OwnerUpdateSucceeds() public {
        uint256 id = _register();
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, false, true);
        emit ProjectUpdated(id, "Metacade Arena", "ipfs://v2", owner);

        vm.prank(owner);
        registry.updateProject(id, "Metacade Arena", "ipfs://v2");

        ProjectHomeRegistry.Project memory p = registry.getProject(id);
        assertEq(p.displayName, "Metacade Arena");
        assertEq(p.metadataURI, "ipfs://v2");
        assertEq(p.slug, "metacade", "slug is immutable");
        assertGt(p.updatedAt, p.createdAt);
    }

    /// Row 5: unauthorized update fails.
    function test_UnauthorizedUpdateReverts() public {
        uint256 id = _register();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ProjectHomeRegistry.NotProjectOwner.selector, id, stranger));
        registry.updateProject(id, "Hijacked", "ipfs://bad");
    }

    /// Row 5b: even the admin cannot rewrite a project's presentation fields.
    function test_AdminCannotUpdateProjectFields() public {
        uint256 id = _register();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ProjectHomeRegistry.NotProjectOwner.selector, id, admin));
        registry.updateProject(id, "Admin Edit", "ipfs://admin");
    }

    /// Row 6: treasury defaults to zero and renders as NOT CONFIGURED.
    function test_TreasuryDefaultsToZero() public {
        uint256 id = _register();
        assertEq(registry.getProject(id).treasury, address(0));
    }

    /// Row 7: nonzero treasury update emits event.
    function test_NonzeroTreasuryUpdateEmitsEvent() public {
        uint256 id = _register();

        vm.expectEmit(true, true, true, false);
        emit TreasuryUpdated(id, address(0), safe);

        vm.prank(admin);
        registry.updateTreasury(id, safe);

        assertEq(registry.getProject(id).treasury, safe);
    }

    function test_TreasuryUpdateRequiresAdmin() public {
        uint256 id = _register();
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, owner, bytes32(0)
            )
        );
        registry.updateTreasury(id, safe);
    }

    function test_TreasuryCanBeClearedBackToNotConfigured() public {
        uint256 id = _register();
        vm.startPrank(admin);
        registry.updateTreasury(id, safe);
        registry.updateTreasury(id, address(0));
        vm.stopPrank();
        assertEq(registry.getProject(id).treasury, address(0));
    }

    /// Row 8: pause or deactivate works.
    function test_DeactivateAndReactivate() public {
        uint256 id = _register();

        vm.expectEmit(true, true, false, true);
        emit ProjectStatusChanged(id, false, admin);

        vm.prank(admin);
        registry.setProjectActive(id, false);
        assertFalse(registry.getProject(id).active);

        vm.prank(admin);
        registry.setProjectActive(id, true);
        assertTrue(registry.getProject(id).active);
    }

    function test_DeactivateRequiresCuratorRole() public {
        uint256 id = _register();
        bytes32 role = registry.CURATOR_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        registry.setProjectActive(id, false);
    }

    /// Row 9: invalid owner fails.
    function test_ZeroOwnerReverts() public {
        vm.prank(admin);
        vm.expectRevert(ProjectHomeRegistry.InvalidOwner.selector);
        registry.registerProject("metacade", "Metacade", address(0), "ipfs://x", HOME_CHAIN_ID);
    }

    function test_EmptySlugReverts() public {
        vm.prank(admin);
        vm.expectRevert(ProjectHomeRegistry.EmptySlug.selector);
        registry.registerProject("", "Metacade", owner, "ipfs://x", HOME_CHAIN_ID);
    }

    function test_ZeroAdminInConstructorReverts() public {
        vm.expectRevert(ProjectHomeRegistry.InvalidOwner.selector);
        new ProjectHomeRegistry(address(0));
    }

    function test_UnknownProjectReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ProjectHomeRegistry.ProjectNotFound.selector, 99));
        registry.getProject(99);
    }

    function test_LookupBySlug() public {
        uint256 id = _register();
        assertEq(registry.getProjectBySlug("metacade").id, id);

        vm.expectRevert(abi.encodeWithSelector(ProjectHomeRegistry.SlugNotFound.selector, "absent"));
        registry.getProjectBySlug("absent");
    }

    /// The registry must never be able to receive value.
    function test_RegistryRejectsEther() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool sent,) = address(registry).call{value: 1 ether}("");
        assertFalse(sent, "registry must not accept value");
    }
}
