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

Exactly two contracts will be deployed and no more. Neither is payable, and tests assert
that a value transfer to either address fails. Nothing is deployed yet: deployment is
gated on explicit gas approval, and `deployments/robinhood-chain.json` records the
addresses once it is given.

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
v0.8.28+commit.7893614a.

---

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — design, and every decision this build made that the spec left open
- [`docs/limitations.md`](docs/limitations.md) — where the guarantees stop, including the off-hours case
- [`docs/buildathon-provenance.md`](docs/buildathon-provenance.md) — what was produced, when, and from which sources
- [`docs/open-house-submission.md`](docs/open-house-submission.md) — submission field answers

## Licence

MIT. See [LICENSE](LICENSE).
