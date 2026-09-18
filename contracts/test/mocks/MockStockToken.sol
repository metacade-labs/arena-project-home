// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Test double for a Robinhood Stock Token corporate-action pause flag.
contract MockStockToken {
    bool private _paused;
    bool public shouldRevert;

    function setPaused(bool v) external {
        _paused = v;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function oraclePaused() external view returns (bool) {
        if (shouldRevert) revert("MockStockToken: no interface");
        return _paused;
    }
}
