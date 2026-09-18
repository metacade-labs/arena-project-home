# Buildathon provenance

What was produced, when, and from which sources.

---

## Window

The Open House Buildathon window runs **14 September to 4 October 2026**, with
submission closing 4 October at 15:59 on the hosting platform.

Every commit in this repository was authored inside that window. The repository was
created from an empty tree; no code was carried in from any earlier project, and no
history was copied from any other repository.

| Item | Value |
|---|---|
| Repository | `metacade-labs/arena-project-home` |
| Visibility | Public |
| First commit | see `git log --reverse` |
| Licence | MIT |

## What was produced here

- `contracts/src/ProjectHomeRegistry.sol` — written for this entry.
- `contracts/src/OracleGuard.sol` — written for this entry.
- `contracts/test/` — 60 unit tests plus 4 live fork tests, written for this entry.
- `apps/web/` — Next.js frontend, written for this entry.
- `docs/` — written for this entry.

## What was not produced here

Third-party libraries, used unmodified and under their own licences:

| Dependency | Version | Why |
|---|---|---|
| OpenZeppelin Contracts | v5.1.0 | `AccessControl`. Audited role-based access is not something to hand-roll. |
| Chainlink contracts | 1.3.0 | `AggregatorV3Interface`, taken from the official package rather than retyped. |
| forge-std | latest | Test harness only. Not deployed. |
| Next.js, React | 16.3.5 / 19.1.1 | Frontend framework. |
| viem | 2.56.5 | Typed Ethereum RPC client for server-side reads. |

No code was taken from Metacade's private repositories. No private environment
variable, private Supabase schema, private product research, unreleased asset or
existing private deployment credential appears anywhere in this repository or its
history.

## Sources of truth for every onchain value

No address in this repository was inferred, remembered or copied from notes. Each was
read from an official source at implementation time and then confirmed by a live
onchain call.

| Value | Source | Confirmation |
|---|---|---|
| Chain ID 4663, RPC, explorer | `docs.robinhood.com/chain/connecting` | `cast chain-id` returned 4663 |
| NVDA feed proxy, decimals, heartbeat, deviation, market hours | Chainlink Data Feeds directory for Robinhood Chain mainnet | `description()` returned `RHNVDA / USD`, `decimals()` returned 8, `version()` returned 6 |
| NVDA aggregator address | Chainlink directory | `aggregator()` on the proxy returned the same address |
| NVDA Stock Token ERC-20 | Robinhood official asset registry, `chainId: 4663` | `symbol()` returned `NVDA`, `oraclePaused()` answered |
| Sequencer uptime feed | Chainlink L2 Sequencer Feeds page and Chainlink's Robinhood directory | Absent from both; none configured |
| Off-hours feed behaviour | `docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood` | Documented, and modelled in the guard |

The Robinhood asset API was used for address discovery at implementation time only. It
is not a runtime dependency: the contracts and the frontend read the chain.

## Conflict found between official sources

Robinhood's oracles page states that Chainlink provides an L2 Sequencer Uptime Feed for
Robinhood Chain. Chainlink's L2 Sequencer Feeds page lists eleven networks and does not
include Robinhood Chain, and Chainlink's machine-readable directory for Robinhood Chain
mainnet contains 57 feeds with no sequencer entry.

This was not reconciled by picking a side. No sequencer address is hardcoded, the
address is left configurable and unset, the affected code paths are implemented and
tested against mocks, and the conflict is recorded in `docs/architecture.md` and
`docs/limitations.md`.

## Evidence

- Unit tests: `forge test` — 60 passing and 4 skipped, no network required. The four
  skipped are the live fork tests; they skip visibly rather than passing vacuously when
  `ROBINHOOD_RPC_URL` is unset.
- Mutation check: three deliberate mutations of the market-session and freshness logic
  were each caught by the suite before the tests were accepted as proof.
- Live fork test: `ROBINHOOD_RPC_URL=... forge test --match-contract OracleGuardForkTest`
  — 4 passing against Robinhood Chain mainnet, reading the real feed.
- CI: contract build, test and format; frontend lint and build; secret scan and
  dependency audit.

## Claims deliberately not made

- Metacade Arena is not live on Robinhood Chain and this repository does not claim it is.
- No partnership with Robinhood, Chainlink, Arbitrum or the Open House programme.
- No grant and no prize.
- The chosen sequencer grace period is this build's constant, not an official parameter.
