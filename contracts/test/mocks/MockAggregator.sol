// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Test double for a Chainlink V3 aggregator proxy.
contract MockAggregator {
    uint8 private _decimals;
    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    bool public shouldRevert;

    constructor(uint8 decimals_, int256 answer_, uint256 updatedAt_) {
        _decimals = decimals_;
        _answer = answer_;
        _updatedAt = updatedAt_;
        _startedAt = updatedAt_;
        _roundId = 1;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    function setStartedAt(uint256 startedAt_) external {
        _startedAt = startedAt_;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function decimals() external view returns (uint8) {
        if (shouldRevert) revert("MockAggregator: down");
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "MOCK / USD";
    }

    function version() external pure returns (uint256) {
        return 6;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        if (shouldRevert) revert("MockAggregator: down");
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (shouldRevert) revert("MockAggregator: down");
        return (_roundId, _answer, _startedAt, _updatedAt, _roundId);
    }
}
