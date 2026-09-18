// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ProjectHomeRegistry
/// @notice Public registry of Arena Project Homes. A Project Home is a public,
///         onchain record of a project: who owns it, where its metadata lives,
///         which chain it calls home, and whether it is active.
/// @dev    The registry holds no value and moves no value. The `treasury` field
///         is a published reference only; this contract has no payable function,
///         no token handling and no withdrawal path. A zero treasury means
///         NOT CONFIGURED and is the default for every newly registered project.
contract ProjectHomeRegistry is AccessControl {
    /// @notice May register new projects.
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    /// @notice May activate or deactivate any project.
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    struct Project {
        uint256 id;
        string slug;
        string displayName;
        address owner;
        string metadataURI;
        uint256 homeChainId;
        address treasury;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    uint256 private _nextId = 1;
    mapping(uint256 => Project) private _projects;
    mapping(bytes32 => uint256) private _idBySlugHash;

    event ProjectRegistered(
        uint256 indexed id, string slug, string displayName, address indexed owner, uint256 homeChainId
    );
    event ProjectUpdated(uint256 indexed id, string displayName, string metadataURI, address indexed by);
    event TreasuryUpdated(uint256 indexed id, address indexed previousTreasury, address indexed newTreasury);
    event ProjectStatusChanged(uint256 indexed id, bool active, address indexed by);

    error EmptySlug();
    error SlugAlreadyRegistered(string slug);
    error ProjectNotFound(uint256 id);
    error SlugNotFound(string slug);
    error InvalidOwner();
    error NotProjectOwner(uint256 id, address caller);
    error TreasuryUnchanged();

    constructor(address admin) {
        if (admin == address(0)) revert InvalidOwner();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
        _grantRole(CURATOR_ROLE, admin);
    }

    /// @notice Register a new Project Home. Treasury always starts unset.
    function registerProject(
        string calldata slug,
        string calldata displayName,
        address owner,
        string calldata metadataURI,
        uint256 homeChainId
    ) external onlyRole(REGISTRAR_ROLE) returns (uint256 id) {
        if (bytes(slug).length == 0) revert EmptySlug();
        if (owner == address(0)) revert InvalidOwner();

        bytes32 slugHash = keccak256(bytes(slug));
        if (_idBySlugHash[slugHash] != 0) revert SlugAlreadyRegistered(slug);

        id = _nextId++;
        _idBySlugHash[slugHash] = id;

        _projects[id] = Project({
            id: id,
            slug: slug,
            displayName: displayName,
            owner: owner,
            metadataURI: metadataURI,
            homeChainId: homeChainId,
            treasury: address(0),
            active: true,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        emit ProjectRegistered(id, slug, displayName, owner, homeChainId);
    }

    /// @notice Update the mutable presentation fields of a project.
    /// @dev    Restricted to the project owner. Slug, id and createdAt are immutable.
    function updateProject(uint256 id, string calldata displayName, string calldata metadataURI) external {
        Project storage p = _requireProject(id);
        if (msg.sender != p.owner) revert NotProjectOwner(id, msg.sender);

        p.displayName = displayName;
        p.metadataURI = metadataURI;
        p.updatedAt = uint64(block.timestamp);

        emit ProjectUpdated(id, displayName, metadataURI, msg.sender);
    }

    /// @notice Set or clear the published treasury reference.
    /// @dev    Admin-only and deliberately separate from updateProject. The registry
    ///         never takes custody; this records an address for readers, nothing more.
    function updateTreasury(uint256 id, address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Project storage p = _requireProject(id);
        address previous = p.treasury;
        if (previous == newTreasury) revert TreasuryUnchanged();

        p.treasury = newTreasury;
        p.updatedAt = uint64(block.timestamp);

        emit TreasuryUpdated(id, previous, newTreasury);
    }

    /// @notice Activate or deactivate a project.
    function setProjectActive(uint256 id, bool active) external onlyRole(CURATOR_ROLE) {
        Project storage p = _requireProject(id);
        p.active = active;
        p.updatedAt = uint64(block.timestamp);

        emit ProjectStatusChanged(id, active, msg.sender);
    }

    function getProject(uint256 id) external view returns (Project memory) {
        return _projects[_requireProject(id).id];
    }

    function getProjectBySlug(string calldata slug) external view returns (Project memory) {
        uint256 id = _idBySlugHash[keccak256(bytes(slug))];
        if (id == 0) revert SlugNotFound(slug);
        return _projects[id];
    }

    /// @notice True when the slug is already taken.
    function slugTaken(string calldata slug) external view returns (bool) {
        return _idBySlugHash[keccak256(bytes(slug))] != 0;
    }

    /// @notice Number of projects registered so far.
    function totalProjects() external view returns (uint256) {
        return _nextId - 1;
    }

    function _requireProject(uint256 id) private view returns (Project storage p) {
        p = _projects[id];
        if (p.id == 0) revert ProjectNotFound(id);
    }
}
