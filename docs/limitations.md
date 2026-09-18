# Limitations

What this build does not do, and where its guarantees stop. Read this before treating
any value on the page as something to act on.

---

## This is a reference implementation, not the Arena

- Metacade Arena is **not** live on Robinhood Chain. This repository deploys a Project
  Home record and an oracle guard. That is all it deploys.
- Fighters, marketplace, wagering, escrow, custody and MCADE conversion are **not** part
  of this build and no code path here implements any of them.
- No partnership with Robinhood, Chainlink, Arbitrum or the Open House programme is
  claimed or implied by this repository. The contracts read public feeds; reading a
  public feed is not a relationship.

## The off-hours case is the important one

Robinhood tokenized-equity feeds trade 24/5. Chainlink states these feeds "do not have
heartbeats during off-hours", and that when the underlying market is closed "the feed
may hold the last published price even though the contract remains callable".

So during a weekend:

- The feed still answers. `latestRoundData()` returns successfully.
- The price it returns may be hours or days old.
- Nothing about the return value distinguishes that from a live price.

`OracleGuard` reports this case as `VALID` with `marketClosed = true`.

**The annotation is the only signal separating a held price from a live one.** A caller
that reads the state and ignores `marketClosed` will treat a stale weekend price as
current. Any surface built on this guard must render both, and this repository's
frontend does: the market-session row is displayed next to the price, and a held price
is labelled as such rather than shown bare.

This MVP displays a price and never converts, quotes, settles or prices anything against
it, so no value is at risk here. That constraint is the reason the held-price allowance
is acceptable at all. Any later surface that would *act* on the value — a swap, a
settlement, a payout — must not accept a `marketClosed` price without its own policy,
and should treat the annotation as a hard block rather than a label.

## Exchange holidays are not modelled

`isMarketClosed()` computes the weekly closure from `block.timestamp` as Saturday or
Sunday UTC. It does not know about Thanksgiving, Christmas, Good Friday or any other
US market holiday, because a holiday calendar is not derivable onchain and no official
onchain calendar is published for this network.

Consequence: on a weekday holiday the session is treated as **open**, so a held price
will report `STALE` rather than `VALID`. That is the conservative direction — the guard
under-trusts rather than over-trusts — but it means a correct feed can be reported as
stale on roughly nine weekdays a year.

`maxHeldStaleness` (5 days) is what bounds a genuinely long closure such as a holiday
weekend, and it applies only while the session is already classified closed.

## Daylight saving shifts the weekly boundary by an hour

The US equity session opens and closes on Eastern time; the contract reasons in UTC.
The Saturday/Sunday UTC window matches the real 24/5 boundary exactly under EDT
(UTC-4). Under EST (UTC-5) the real boundary moves an hour later, so for up to one hour
around each weekly edge the classification can be off by one hour. Within that hour the
feed is live and well inside its heartbeat, so the practical effect is nil, but the
approximation is stated here rather than hidden.

## The pause flag is advisory

`oraclePaused()` reports that Robinhood has paused publishing for a corporate action.
It is **not enforced onchain**: a paused token can still return a value, and nothing
prevents a caller reading straight through it. It is reported, never relied on as the
sole guard. Timestamp freshness is the primary guard and is evaluated first.

A Stock Token that does not expose `oraclePaused()` is handled — the call is caught and
the read continues without the pause signal.

## No sequencer uptime feed is configured on this network

Robinhood's documentation states that Chainlink provides an L2 Sequencer Uptime Feed.
Chainlink's L2 Sequencer Feeds page lists eleven networks and does not include Robinhood
Chain, and Chainlink's directory for Robinhood Chain mainnet contains no sequencer entry.

No official address could be found, so none is configured. `sequencerUptimeFeed` is
`address(0)` and the sequencer checks are skipped. **While it is unset, this guard
cannot detect a sequencer outage**, which on an Arbitrum L2 is a real failure mode: a
downed sequencer can leave a feed frozen while it still answers.

The `SEQUENCER_DOWN` and `GRACE_PERIOD` paths are implemented and tested against mocks,
and an admin can point the guard at a real feed as soon as one is published. The
conflict between the two official sources is unresolved and has been raised rather than
reconciled.

## The grace period is a chosen number

`SEQUENCER_GRACE_PERIOD = 3600` is this build's choice, matching the value in
Chainlink's own example. Robinhood Chain publishes no grace period. It is not an
official parameter and must not be cited as one.

## The public RPC is rate-limited

Robinhood documents the public endpoint as rate-limited and not recommended for
production. Reads at this scale are fine, and the live fork test needed one retry after
a connection reset during the run. A frontend under real traffic would need a dedicated
provider endpoint.

## Access control is role-based, not governance

Both contracts use OpenZeppelin `AccessControl` with an admin address. There is no
timelock, no multisig requirement enforced in code, and no onchain governance. Whoever
holds `DEFAULT_ADMIN_ROLE` can reconfigure assets and set the treasury reference. For a
reference implementation that holds no value this is proportionate; anything holding
value would need more.

## A project owner key cannot be replaced

`ProjectHomeRegistry` has no owner-transfer function and no admin recovery path. The
project owner set at registration is the only address that can ever update that
project's display name and metadata URI. If that key is lost the record's presentation
fields are frozen permanently; the admin can still deactivate the project and set the
treasury reference, but cannot reassign ownership.

This is deliberate for a reference implementation — an admin able to reassign ownership
is an admin able to take over any record — but it is a real operational constraint and
is stated here rather than discovered later.

## What the contracts cannot do

Neither contract is payable. Neither holds, transfers, swaps, escrows or converts any
token. `test_RegistryRejectsEther` and `test_GuardRejectsEther` assert that a plain
value transfer to either address fails. There is no upgrade proxy and no admin function
that can move value, because there is no value to move.
