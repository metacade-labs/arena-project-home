#!/usr/bin/env bash
# Installs the pinned Foundry dependencies into lib/.
# Versions are pinned here and nowhere else. lib/ is not committed: it is 27MB of
# third-party source that would bury the code this repository is actually for.
set -euo pipefail

forge install foundry-rs/forge-std@v1.16.2 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 --no-git

echo "Contract dependencies installed."
