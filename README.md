# Arena Project Home

A public reference implementation of an **Arena Project Home**: a project registered
onchain, and one official Chainlink feed read through a guard that returns an explicit
validity state rather than a bare price.

Built for Robinhood Chain mainnet (chain ID 4663).

---

## What this is, and what it is not

**It is** two contracts, a test suite, and a read-only public page that reads them live.

**It is not** Metacade Arena. The Arena is not live on Robinhood Chain. Fighters,
marketplace, wagering, escrow, custody and MCADE conversion are not part of this build
and no code path here implements any of them.

No partnership with Robinhood, Chainlink, Arbitrum or the Open House programme is
claimed or implied. These contracts read public feeds.

---

## The problem it addresses

Robinhood's tokenized equity feeds trade 24/5. Per Chainlink, these feeds "do not have
heartbeats during off-hours", and when the underlying market closes "the feed may hold
the last published price even though the contract remains callable".

So a naive integration has two failure modes, and they point in opposite directions:

- A plain `latestRoundData()` read treats a two-day-old weekend price as current.
- A plain maximum-age check reports a perfectly healthy feed as `STALE` every weekend.

`OracleGuard` separates them. A held price during a closed session is `VALID` with a
`marketClosed` annotation. The same age during an open session is `STALE`. Two tests
assert exactly that pair, using the same price age and expecting opposite states.

---

## Contracts

| Contract | Purpose |
|---|---|
| `ProjectHomeRegistry` | Public record of a project: slug, owner, metadata URI, home chain, treasury reference, active flag. Holds no value. |
| `OracleGuard` | Returns an explicit `OracleState` for one official Chainlink feed. Holds no value, converts nothing, has no fallback price source. |

Exactly two contracts are deployed and no more. Neither is payable, and tests assert
that a value transfer to either address fails. Both are live on Robinhood Chain Mainnet:

| Contract | Address |
|---|---|
| `ProjectHomeRegistry` | `0x7a194166BD8ABb6Aa3bD924532b8c7CA59a05D15` |
| `OracleGuard` | `0x5014BeFb2EE7AA9e29163a75e7989983Df8D2048` |

Every role on both is held by `0x70C851895247e7ACa99733EA3aaC1FFb247c1423`; the deployer
renounced all of them. `deployments/robinhood-chain.json` records the addresses, every
transaction hash and the `hasRole` reads, all taken from receipts and chain reads.

### Oracle states

| State | Meaning |
|---|---|
| `UNSUPPORTED` | No official feed configured. Index 0, so an uninitialised read is never `VALID`. |
| `VALID` | Feed answered, answer positive, within the freshness bound for the current session. |
| `STALE` | Older than the bound that applies to the current session. |
| `SEQUENCER_DOWN` | L2 sequencer reported down. |
| `GRACE_PERIOD` | Sequencer recently recovered; values withheld until the grace period elapses. |
| `ORACLE_PAUSED` | Corporate-action pause. Advisory only, not enforced onchain. |
| `INVALID_ANSWER` | Non-positive answer, unset round, future timestamp, or a reverting feed. |

---

## Selected feed

Read from the official Chainlink Data Feeds directory for Robinhood Chain mainnet and
confirmed by live onchain reads.

| Parameter | Value |
|---|---|
| Feed | Robinhood NVDA / USD |
| Proxy | `0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15` |
| Onchain `description()` | `RHNVDA / USD` |
| Decimals | 8 |
| Heartbeat | 86,400s, deviation 0.5% |
| Market hours | `us_equities_24/5` |
| Stock Token ERC-20 | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` |

---

## Layout

```
contracts/src/       ProjectHomeRegistry.sol, OracleGuard.sol
contracts/test/      unit tests, mocks, and a live fork test
contracts/script/    Deploy.s.sol
apps/web/            Next.js App Router frontend, server-side live chain reads
deployments/         deployed addresses and oracle configuration
docs/                architecture, limitations, provenance, submission pack
```

---

## Running it

Requires Foundry and pnpm.

```bash
forge build
forge test                 # 65 unit tests, no network needed; 4 fork tests skip

# live fork proof against Robinhood Chain mainnet
ROBINHOOD_RPC_URL=https://rpc.mainnet.chain.robinhood.com forge test --match-contract OracleGuardForkTest -vv

pnpm install
pnpm dev                   # http://localhost:3000/project/metacade
```

The frontend works before the contracts are deployed: it reads the official Chainlink
proxy directly and labels the state source as `DIRECT FEED`. Once
`NEXT_PUBLIC_ORACLE_GUARD_ADDRESS` and `NEXT_PUBLIC_REGISTRY_ADDRESS` are set it reads
the deployed contracts instead and labels the source `ORACLEGUARD`.

### Configuration

| Variable | Purpose |
|---|---|
| `ROBINHOOD_RPC_URL` | JSON-RPC endpoint. Defaults to the public endpoint, which is rate-limited. |
| `NEXT_PUBLIC_REGISTRY_ADDRESS` | Deployed `ProjectHomeRegistry`. |
| `NEXT_PUBLIC_ORACLE_GUARD_ADDRESS` | Deployed `OracleGuard`. |
| `ROBINHOOD_CHAIN_ID` | Network the frontend reads: `4663` (default) or `46630` for the testnet rehearsal. Any other value fails loudly. |
| `ROBINHOOD_TESTNET_RPC_URL` | Testnet JSON-RPC endpoint. Defaults to the public testnet endpoint. |
| `DEPLOY_ADMIN` | Admin address for the deploy script. Must be the broadcasting account. |
| `PROJECT_OWNER` | Project owner recorded in the registry. Defaults to `DEPLOY_ADMIN`. |
| `MOCK_NVDA_ANSWER` | Testnet only. Seed answer for the rehearsal mock feed, 8 decimals. |

No secret belongs in any `NEXT_PUBLIC_` variable. The deployment signer is never read
by the frontend and never leaves the local environment.

### Deploying

`contracts/script/Deploy.s.sol` selects its configuration by `block.chainid`:

| Chain | What it deploys |
|---|---|
| 4663, mainnet | `ProjectHomeRegistry` and `OracleGuard`, the guard pointed at the official Chainlink proxy and Robinhood Stock Token. Nothing else. |
| 46630, testnet | A `MockAggregator` first, as rehearsal scaffolding, then the same two contracts with the guard pointed at the mock. Chainlink publishes no Robinhood feed on testnet. |
| anything else | Reverts before sending a transaction. |

```bash
# simulate; no transaction is sent
DEPLOY_ADMIN=<deployer> forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url <rpc> --sender <deployer>

# after a real --broadcast, record addresses and transaction hashes
node scripts/record-deployment.mjs 46630   # writes deployments/robinhood-chain-testnet.json
node scripts/record-deployment.mjs 4663    # writes deployments/robinhood-chain.json
```

The recorder reads forge's broadcast output and receipts, never hand-typed values, and
its chain id selects the output file. A testnet run has no path to the mainnet record.

### Role handoff

The deployer is a temporary admin. Straight after the deploy, in the same session:

```bash
# PROJECT_OWNER must be the new admin at deploy time: the registry cannot change a
# project owner after registration, and the handoff script refuses to run otherwise.
DEPLOY_ADMIN=<deployer> PROJECT_OWNER=<new admin> forge script contracts/script/Deploy.s.sol:Deploy ...

REGISTRY_ADDRESS=<registry> ORACLE_GUARD_ADDRESS=<guard> NEW_ADMIN=<new admin> \
  forge script contracts/script/HandoffRoles.s.sol:HandoffRoles ...

node scripts/record-roles.mjs <chainId> <new admin>
```

`HandoffRoles` sends ten transactions: it grants `DEFAULT_ADMIN_ROLE`, `REGISTRAR_ROLE`
and `CURATOR_ROLE` on the registry and `DEFAULT_ADMIN_ROLE` and `ASSET_MANAGER_ROLE` on
the guard to the new admin, then renounces all five from the deployer, admin role last.
It checks the end state before exiting. `record-roles.mjs` then reads all ten `hasRole`
answers at one block and writes them to the deployment record only if the deployer holds
none of the roles and the new admin holds all five.

### Source verification

Proven on the testnet rehearsal on 2026-09-21: all three contracts reached
`is_fully_verified: true` on `explorer.testnet.chain.robinhood.com` (Blockscout v10.2.6)
with this command, once per contract. Both production contracts take a single
`constructor(address admin)`.

```bash
forge verify-contract <address> contracts/src/OracleGuard.sol:OracleGuard \
  --chain 46630 \
  --verifier blockscout \
  --verifier-url https://explorer.testnet.chain.robinhood.com/api/ \
  --constructor-args $(cast abi-encode "constructor(address)" <admin>) \
  --compiler-version 0.8.28 \
  --watch
```

For mainnet, substitute `--chain 4663` and
`--verifier-url https://robinhoodchain.blockscout.com/api/`. That explorer's API sits
behind Cloudflare and has refused datacentre traffic, so the second route is the
Blockscout web form: generate the input with
`forge verify-contract <address> <path>:<name> --show-standard-json-input > <name>.json`
and upload it under "Verify & Publish" as Solidity standard JSON input, compiler
v0.8.28+commit.7893614a. The standard JSON input does not carry constructor arguments.
If the form asks for them, supply the ABI-encoded admin from
`cast abi-encode "constructor(address)" <admin>`, which is also recorded in the
creation transaction's input after the bytecode.

---

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — design, and every decision this build made that the spec left open
- [`docs/limitations.md`](docs/limitations.md) — where the guarantees stop, including the off-hours case
- [`docs/buildathon-provenance.md`](docs/buildathon-provenance.md) — what was produced, when, and from which sources
- [`docs/open-house-submission.md`](docs/open-house-submission.md) — submission field answers

## Licence

MIT. See [LICENSE](LICENSE).
