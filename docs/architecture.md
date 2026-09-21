# Architecture

Arena Project Home is a public reference implementation of two contracts and one
read-only frontend. It registers a project onchain and reads one official Chainlink
feed through a guard that returns an explicit validity state rather than a bare number.

It is a reference implementation. The wider Metacade Arena is not live on Robinhood Chain.

---

## Network

| Parameter | Value | Source |
|---|---|---|
| Network | Robinhood Chain Mainnet | docs.robinhood.com/chain/connecting |
| Chain ID | 4663 | docs.robinhood.com/chain/connecting, confirmed by `cast chain-id` |
| Native gas token | ETH | docs.robinhood.com/chain/connecting |
| Public RPC | `https://rpc.mainnet.chain.robinhood.com` | docs.robinhood.com/chain/connecting |
| Explorer | `https://robinhoodchain.blockscout.com` | docs.robinhood.com/chain/connecting |
| Chain type | Arbitrum Layer-2 on Ethereum | docs.robinhood.com/chain |

A Robinhood Chain testnet exists (chain ID 46630, `https://rpc.testnet.chain.robinhood.com`,
explorer `https://explorer.testnet.chain.robinhood.com`). It is used for one job: a
deployment rehearsal. Chainlink publishes no price feeds on any Robinhood test network,
and the mainnet proxy address has no code there, so the tokenized-equity feed this
reference is built around cannot be read on testnet. The deploy script therefore deploys
a `MockAggregator` on 46630 and points the guard at it. That proves the deploy script,
the access-control wiring, explorer verification and the frontend read path. It proves
nothing about the live feed; that proof is the mainnet fork test. Testnet addresses are
recorded in `deployments/robinhood-chain-testnet.json` and never in the submission pack.

The public RPC is rate-limited and documented as unsuitable for production. It is
adequate for reads at this scale and is what the fork test and frontend use by default.

---

## Contracts

Exactly two contracts are deployed. Nothing else takes an address. On Robinhood Chain
Mainnet they are `ProjectHomeRegistry` at `0x7a194166BD8ABb6Aa3bD924532b8c7CA59a05D15`
and `OracleGuard` at `0x5014BeFb2EE7AA9e29163a75e7989983Df8D2048`. The deployer was a
temporary admin: straight after the deploy it granted every role to
`0x70C851895247e7ACa99733EA3aaC1FFb247c1423` and renounced its own, admin role last
(`contracts/script/HandoffRoles.s.sol`). The registered project owner was set to the same
address at registration, because the registry cannot change an owner afterwards.

### ProjectHomeRegistry

A public record of a project: id, slug, display name, owner, metadata URI, home chain,
treasury reference, active flag, and created/updated timestamps.

Access control is OpenZeppelin `AccessControl`:

- `REGISTRAR_ROLE` registers new projects.
- `CURATOR_ROLE` activates and deactivates.
- `DEFAULT_ADMIN_ROLE` sets the treasury reference.
- The **project owner**, and only the project owner, updates display name and metadata URI.
  The admin cannot rewrite a project's presentation fields. This is asserted in
  `test_AdminCannotUpdateProjectFields`.

Slug and id are immutable after registration. Slugs are unique, keyed by `keccak256`.

**Treasury is `address(0)` at registration, always.** It renders as `NOT CONFIGURED`.
The registry holds no value: there is no payable function, no token handling and no
withdrawal path, and `test_RegistryRejectsEther` asserts that a plain value transfer
to the contract fails. A treasury address, if ever set, is a published reference for
readers and nothing more. The deployment wallet must never be used as the treasury.

### OracleGuard

Reads one official Chainlink feed and returns a `PriceStatus`, not a price.

```
enum OracleState {
    UNSUPPORTED,     // 0
    VALID,
    STALE,
    SEQUENCER_DOWN,
    GRACE_PERIOD,
    ORACLE_PAUSED,
    INVALID_ANSWER
}
```

Checks run in this order:

1. **Asset configured.** Unconfigured reads `UNSUPPORTED`.
2. **Sequencer up**, where such a feed exists on the network.
3. **Grace period elapsed** since the sequencer last changed status.
4. **Answer sane.** Non-positive, unset-round, reverting or future-dated reads `INVALID_ANSWER`.
5. **Freshness**, gated on market session for tokenized equities.
6. **Corporate-action pause**, advisory, checked last.

`decimals()` is read from the feed on every call and never assumed. A feed that answers
with a price but will not report its scale is treated as not having answered at all and
reports `INVALID_ANSWER`: a price read against a guessed scale is worse than no price,
and the natural fallback of zero is the single worst guess available, inflating every
value by 10^18. Values are normalised to 18 decimals for comparison; the raw answer is
also returned.

Normalisation cannot revert. Three cases are out of band and report `INVALID_ANSWER`
rather than bubbling an arithmetic error out of a status function: a decimals value
above `MAX_PLAUSIBLE_DECIMALS` (36), an answer large enough that scaling up would
overflow `int256`, and an answer small enough that scaling down collapses it to zero.

`checkPrice` never reverts. A feed that reverts, or that returns a value the guard
cannot scale, is caught and reported as `INVALID_ANSWER`, because a status function that
reverts gives the caller nothing to render.

---

## Decisions this build made that the specification left open

### `UNSUPPORTED` is the zero value

Solidity enums default to index 0. Making `VALID` the zero value would mean any
uninitialised or garbage read degrades to "trusted". `UNSUPPORTED` occupies index 0 so
that the failure direction is safe. Asserted in `test_UnsupportedIsTheZeroValue`.

### An unset round is folded into `INVALID_ANSWER`

There is no eighth state. `updatedAt == 0` reports `INVALID_ANSWER` alongside
non-positive and future-dated answers. The condition is the same for a caller: the feed
did not return something that can be treated as a price.

### The sequencer grace period is 3600 seconds, and it is ours, not Robinhood's

Chainlink documents the shape — `sequencerStatus == 0` for up, plus a requirement that
`block.timestamp - startedAt` exceed a grace period — but publishes no value for this
network. `SEQUENCER_GRACE_PERIOD = 3600` matches the constant used in Chainlink's own
L2 sequencer example. **It is a chosen value and is not an official Robinhood Chain
parameter.** It is a public constant so any reader can see exactly what was chosen.

### The sequencer uptime feed address is configurable and currently unset

Two official sources disagree:

- Robinhood's oracles page states that "Chainlink provides an L2 Sequencer Uptime Feed".
- Chainlink's L2 Sequencer Feeds page lists eleven networks and **does not include
  Robinhood Chain**, and Chainlink's machine-readable directory for Robinhood Chain
  mainnet contains 57 feeds and no sequencer entry.

No sequencer uptime feed address for Robinhood Chain could be found in any official
directory, so none is hardcoded. `sequencerUptimeFeed` defaults to `address(0)`, which
skips the sequencer checks, and an admin can set it the moment one is published. The
`SEQUENCER_DOWN` and `GRACE_PERIOD` paths are fully implemented and tested against
mocks so the behaviour is proven and ready. This conflict is unresolved and is raised
for the oversight layer rather than silently reconciled.

### Freshness is gated on market session

Robinhood tokenized-equity feeds run 24/5 and, per Chainlink, "do not have heartbeats
during off-hours"; when the market closes "the feed may hold the last published price
even though the contract remains callable".

A single maximum-age check would therefore report `STALE` for every reader during a
weekend. That is a false alarm, and it would misrepresent a healthy feed as a broken one.

Two bounds are configured per asset:

- `maxStaleness` — applies while the session is open. Set to 90,000s for NVDA: the
  official 86,400s heartbeat plus one hour of headroom.
- `maxHeldStaleness` — applies while the session is closed. Set to 432,000s (5 days).
  A held price is accepted, but not indefinitely; past this ceiling it reads `STALE`
  even on a weekend, which bounds the case where a feed genuinely dies over a long close.

`isMarketClosed()` computes the weekly closure from `block.timestamp` as Saturday or
Sunday UTC. Exchange holidays are not derivable onchain and are not modelled; the
`maxHeldStaleness` ceiling is what bounds a long closure. See `docs/limitations.md`.

A held price during a closed session reports `VALID` with `marketClosed = true`. The
paired tests `test_HeldPriceDuringClosedSessionIsValidAndAnnotated` and
`test_SameAgeIsStaleOnAnOpenSession` use the same price age and assert opposite states,
which is what proves the two conditions are distinguished rather than collapsed.

### Freshness outranks the pause flag

Robinhood's pause interface is advisory: `oraclePaused()` reports intent, but it is not
enforced onchain and a paused token may still return a value. Freshness is therefore the
primary guard and is evaluated first. A feed that is both paused and stale reports
`STALE`, not `ORACLE_PAUSED` — asserted in `test_StalenessTakesPrecedenceOverPauseFlag`.

`oraclePaused()` lives on the **Stock Token ERC-20**, not on the Chainlink proxy, so the
guard stores both addresses per asset. A token that does not expose the interface is
handled: the call is caught and the read continues.

---

## Selected feed

Read from the official Chainlink Data Feeds directory for Robinhood Chain mainnet and
confirmed by live onchain reads.

| Parameter | Value |
|---|---|
| Feed | Robinhood NVDA / USD |
| Proxy | `0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15` |
| Onchain `description()` | `RHNVDA / USD` |
| Aggregator | `0xC9d16E4f2569b9E3ea0468fD85844953713DC2a2` |
| Decimals | 8 |
| Aggregator version | 6 |
| Heartbeat | 86,400s |
| Deviation threshold | 0.5% |
| Market hours | `us_equities_24/5` |
| Asset class | Equity |
| Stock Token ERC-20 | `0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC` |
| Token decimals | 18 |

The Stock Token address was read from Robinhood's official asset registry
(`api.robinhood.com/rhj/assets`, `chainId: 4663`) at implementation time. That API is
used for address discovery only. It is not used at runtime: the contracts and the
frontend read the chain.

The Chainlink price already includes the corporate-action multiplier. The guard does
**not** apply `uiMultiplier()` itself, per Robinhood's explicit instruction not to.

---

## Frontend

Next.js App Router, server components, `viem`. One route: `/project/metacade`.

Every displayed value is a live chain read against Robinhood Chain mainnet. There is no
database, no authentication, no private API and no wallet connection. The page reads;
it cannot write.

State labels distinguish what exists from what does not: `LIVE`, `BUILT`, `FUTURE`.
