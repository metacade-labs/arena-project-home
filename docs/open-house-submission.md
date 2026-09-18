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

**GATED.** No contract is deployed. Deployment to Robinhood Chain mainnet requires
explicit gas approval, which has not been given. Once deployed this field takes the
`ProjectHomeRegistry` address, and `deployments/robinhood-chain.json` is updated in the
same change.

## Prize tracks

> Overall Prize; Promising Products Track; Grants

*(47 characters)*


## Frontend URL

See **Deployment status** below. Until that section carries a URL, this field has no
answer and must not be filled in with a guess.

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

> All of it. The repository was created inside the window from an empty tree: both contracts, 60 unit tests, 4 live fork tests against Robinhood Chain mainnet, the frontend, CI and the docs. OpenZeppelin, Chainlink, Next.js and viem are used unmodified.

*(251 characters)*

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
| `ProjectHomeRegistry` | Not deployed. Gated on explicit gas approval. |
| `OracleGuard` | Not deployed. Gated on explicit gas approval. |
| Source verification | Not applicable until deployed. Blockscout exposes a contract-verification page for this chain; whether it verifies solc 0.8.28 standard-JSON input could not be confirmed from the build environment and is to be settled at deploy time. |
| Public frontend URL | Deployed and rendering, but **not publicly reachable**. See below. |

The frontend is deployed and the build is healthy. Fetched with Vercel authentication,
it returns HTTP 200 and renders live Robinhood Chain data — chain head read live, the
NVDA feed reporting `VALID` at its real price, market session `OPEN`, and the
not-yet-deployed contract rows correctly showing `NOT CONFIGURED`.

It is **not publicly reachable**. The Vercel project has SSO deployment protection
enabled with `deploymentType: all_except_custom_domains`, so an anonymous request to the
generated domain is redirected to a Vercel SSO page. A judge opening the link would see
a login screen, not the page.

No URL is claimed in the Frontend URL field until that is resolved, because a link that
demands a Vercel login is worse than no link. Resolving it is a project-settings change
on the hosting account, not a code change; nothing in this repository needs to alter.

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
- No contract address is claimed, because nothing is deployed.

## Repository

> https://github.com/metacade-labs/arena-project-home
