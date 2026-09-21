# Open House submission pack

Exact field answers. **This form has not been submitted and the team has not been
registered.** Both are Russell's actions. This document is the prepared content only.

Character counts below are generated from the answer text, not estimated. Every field
with a 300-character limit is under it.

---

## Selected project

> Metacade — Arena Project Home

*(29 characters)*


## Primary contract address

> 0x7a194166BD8ABb6Aa3bD924532b8c7CA59a05D15

*(42 characters)*

`ProjectHomeRegistry` on Robinhood Chain Mainnet (chain ID 4663). The second contract,
`OracleGuard`, is `0x5014BeFb2EE7AA9e29163a75e7989983Df8D2048`. Both addresses, and the transaction hash of every deployment
and role transaction, are in `deployments/robinhood-chain.json`, written from the
broadcast receipts after each was re-fetched from the chain.

## Prize tracks

> Overall Prize; Promising Products Track; Grants

*(47 characters)*


## Frontend URL

> https://arena-project-home.vercel.app/project/metacade

*(54 characters)*

## Core contracts

> ProjectHomeRegistry records a project onchain: slug, owner, metadata URI, home chain, treasury reference, active flag. OracleGuard returns an explicit validity state for one official Chainlink feed instead of a bare price. Neither is payable; neither takes custody.

*(265 characters)*

## Factory or pool contracts

> None. This entry deploys exactly two contracts and no factory, pool, router or proxy.

*(85 characters)*

## Token contract

> None. This project deploys no token. It reads an official Chainlink feed for a Robinhood Stock Token it does not issue, and performs no swap, conversion or settlement.

*(167 characters)*

## Code produced during Buildathon

> All of it. The repository was created inside the window from an empty tree: both contracts, the deploy and role handoff scripts, 70 unit tests, 4 live fork tests against Robinhood Chain mainnet, the frontend, CI and the docs. OpenZeppelin, Chainlink, Next.js and viem are used unmodified.

*(288 characters)*

## Sponsor technologies used

> Robinhood Chain — deployment target and the network every read is made against. OpenZeppelin — AccessControl in both contracts. Chainlink — the tokenized equity feed OracleGuard validates, read through the official V3 aggregator proxy.

*(235 characters)*


Alchemy and AWS are **not** claimed: neither is used in the delivered build. The public
Robinhood Chain RPC is used directly.

Chainlink does not appear in the sponsor selector. It is described in narrative and
evidenced throughout the repository, and is **not** claimed as a partnership.

---

## Deployment status

| Item | State |
|---|---|
| Public repository | Live — https://github.com/metacade-labs/arena-project-home |
| `ProjectHomeRegistry` | Deployed — `0x7a194166BD8ABb6Aa3bD924532b8c7CA59a05D15` |
| `OracleGuard` | Deployed — `0x5014BeFb2EE7AA9e29163a75e7989983Df8D2048`, configured against the official Chainlink proxy for Robinhood NVDA / USD |
| Admin | Every role on both contracts is held by `0x70C851895247e7ACa99733EA3aaC1FFb247c1423`, which is also the registered project owner. The deployer renounced all five roles; the `hasRole` reads proving it are recorded in `deployments/robinhood-chain.json` under `roleHandoff`. |
| Source verification | Verified, exact match (not partial), on robinhoodchain.blockscout.com for both contracts. `ProjectHomeRegistry` at 2026-09-21 06:39:23 and `OracleGuard` at 2026-09-21 07:02:15, explorer time. Both: compiler v0.8.28+commit.7893614a, EVM cancun, optimizer enabled, 200 runs; constructor argument `admin` = `0x451b561485069d5983118aD2bA3d80b88B0A5100`, read by the explorer from the creation transaction. Source, ABI and read/write tabs are public. |
| Public frontend URL | Live and publicly reachable — https://arena-project-home.vercel.app/project/metacade |

The frontend is reachable anonymously and reads the deployed contracts. It is hosted in
the Metacade Vercel team and was fetched on 2026-09-21 at 13:27:14 UTC with no Vercel
session, no cookie and no bypass token. It returned HTTP 200 with no redirect and no
`Set-Cookie`, and rendered: state source `ORACLEGUARD`, oracle state `VALID` at the
feed's real price, market session `OPEN`, chain head block 68,832,007, both contract
addresses, registry record id 1 `ACTIVE`, and project owner
`0x70C851895247e7ACa99733EA3aaC1FFb247c1423`. The only rows still reading
`NOT CONFIGURED` are the treasury, which this build deliberately leaves unset, and the
sequencer uptime feed, which Robinhood Chain does not publish.

The closed-session rendering (price shown, session `CLOSED`, state `VALID` with the
`marketClosed` annotation, not `STALE`) is asserted by tests but has not yet been
observed live: the market was open at every check made so far. It can first be checked
live from Saturday 2026-09-26 00:00 UTC.

The Vercel project keeps SSO deployment protection at `all_except_custom_domains`.
`arena-project-home.vercel.app` is a domain assigned to the project, which that mode
exempts; per-deployment URLs redirect to a Vercel login. The Frontend URL field names the
project domain only.

---

## What the entry actually demonstrates

The interesting problem is off-hours behaviour on tokenized equity feeds, and the
judging window falls entirely inside a market closure.

Robinhood's tokenized equity feeds trade 24/5. Chainlink states these feeds "do not
have heartbeats during off-hours", and that when the market closes "the feed may hold
the last published price even though the contract remains callable".

That leaves two ways to be wrong, pointing in opposite directions:

- A plain `latestRoundData()` read treats a two-day-old weekend price as current.
- A plain maximum-age check reports a healthy feed as `STALE` every single weekend —
  including the entire judging window.

`OracleGuard` separates them. Freshness is gated on market session, so a held price
during a closed session reports `VALID` with a `marketClosed` annotation, while the
same price age during an open session reports `STALE`. Two tests assert exactly that,
using identical price ages and expecting opposite states.

## Claims deliberately not made

- Metacade Arena is **not** live on Robinhood Chain. This is a Project Home reference
  implementation.
- No partnership with Robinhood, Chainlink, Arbitrum or the Open House programme.
- No grant and no prize.
- Fighters, marketplace, wagering, escrow, custody and MCADE conversion are not part of
  this build.
- The sequencer grace period constant is this build's choice, not an official parameter.

## Repository

> https://github.com/metacade-labs/arena-project-home
