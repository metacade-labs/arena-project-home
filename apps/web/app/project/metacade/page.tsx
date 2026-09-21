import {readChainHead, readOracle, readProject} from "../../../lib/chain";
import {
  chainConfig,
  deployedContracts,
  oracleConfig,
  projectConfig,
  explorerAddressUrl
} from "../../../lib/config";
import {
  AddressLink,
  Badge,
  NotConfigured,
  Row,
  StateLabel,
  formatAge,
  formatUtc
} from "../../../components/Primitives";
import {OracleStatePanel} from "../../../components/OracleStatePanel";

// Every request reads the chain. A cached price would defeat the point of the guard.
export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function ProjectHomePage() {
  const [head, oracle, projectResult] = await Promise.all([
    readChainHead(),
    readOracle(),
    readProject()
  ]);
  const project = projectResult.status === "ok" ? projectResult.project : null;

  // Absence and failure are different answers. Saying "not deployed" because a read
  // failed would be a confident wrong answer, which is the one thing this page must
  // not produce.
  const registryAbsenceReason =
    projectResult.status === "not-deployed"
      ? "deployment gated on gas approval"
      : "registry read failed; deployment state unknown";

  // The session flag comes from the same read as the price, so the badge and the
  // state can never disagree. When the guard is deployed this is the guard's own value.
  const marketClosed = oracle.marketClosed;
  const registryAddress = deployedContracts.projectHomeRegistry;
  const guardAddress = deployedContracts.oracleGuard;

  return (
    <main className="page">
      <header className="masthead">
        <p className="eyebrow">Arena Project Home — reference implementation</p>
        <h1>{projectConfig.displayName}</h1>
        <p className="summary">{projectConfig.summary}</p>
        <ul className="tag-list" aria-label="Maturity">
          <li>
            <StateLabel state="BUILT" /> <span className="dim">Project Home reference</span>
          </li>
          <li>
            <StateLabel state="LIVE" /> <span className="dim">Chainlink feed read</span>
          </li>
          <li>
            <StateLabel state="FUTURE" /> <span className="dim">Everything below</span>
          </li>
        </ul>
      </header>

      {chainConfig.isRehearsal ? (
        <div className="notice">
          <h2>Testnet rehearsal</h2>
          <ul>
            <li>
              This render reads <strong>{chainConfig.name}</strong>. The guard here reads a mock
              aggregator deployed for the rehearsal, not a Chainlink feed. No price below is real.
            </li>
          </ul>
        </div>
      ) : null}

      <div className="notice">
        <h2>Read this before anything else on the page</h2>
        <ul>
          <li>
            This Project Home reference is <strong>BUILT</strong>: two contracts and a read-only page.
          </li>
          <li>
            The wider Metacade Arena is <strong>not live on Robinhood Chain</strong>. Nothing here
            runs the game.
          </li>
          <li>
            Fighters, marketplace, wagering, custody and MCADE conversion are{" "}
            <strong>FUTURE</strong> and are not part of this build. No code path here implements any
            of them.
          </li>
          <li>
            No partnership with Robinhood, Chainlink or Arbitrum is claimed. These contracts read
            public feeds.
          </li>
        </ul>
      </div>

      <section aria-labelledby="project-heading">
        <h2 id="project-heading">Project</h2>
        <dl className="rows">
          <Row label="Name">{projectConfig.displayName}</Row>
          <Row label="Slug">
            <span className="mono">{projectConfig.slug}</span>
          </Row>
          <Row label="Current Arena zone">
            {projectConfig.arenaZone} <StateLabel state="LIVE" />
          </Row>
          <Row label="Next progression">
            {projectConfig.nextProgression} <StateLabel state="FUTURE" />
          </Row>
          <Row label="Home chain">
            {chainConfig.name} <span className="dim">(chain ID {chainConfig.id})</span>
          </Row>
          <Row label="Project owner">
            {project ? (
              <AddressLink address={project.owner} />
            ) : (
              <NotConfigured reason={registryAbsenceReason} />
            )}
          </Row>
          <Row label="Treasury">
            {project ? (
              project.treasury !== "0x0000000000000000000000000000000000000000" ? (
                <AddressLink address={project.treasury} />
              ) : (
                <NotConfigured reason="this build takes no custody" />
              )
            ) : (
              // Without a registry read we have not learned the treasury is unset,
              // only that we could not look.
              <NotConfigured reason={registryAbsenceReason} />
            )}
          </Row>
          <Row label="Registry record">
            {project ? (
              <>
                <span className="mono">id {project.id.toString()}</span>{" "}
                <Badge tone={project.active ? "good" : "warn"}>
                  {project.active ? "ACTIVE" : "INACTIVE"}
                </Badge>
              </>
            ) : (
              <NotConfigured reason={registryAbsenceReason} />
            )}
          </Row>
        </dl>
      </section>

      <section aria-labelledby="oracle-heading">
        <h2 id="oracle-heading">Validated price</h2>
        <dl className="rows">
          <Row label="Selected asset">
            {oracleConfig.feedName} <span className="dim">({oracleConfig.assetName})</span>
          </Row>
          <Row label="Validated price">
            {oracle.price ? (
              <span className="price">
                {Number(oracle.price).toLocaleString("en-US", {
                  style: "currency",
                  currency: "USD",
                  minimumFractionDigits: 2,
                  maximumFractionDigits: 4
                })}
              </span>
            ) : (
              <span className="dim">no validated price</span>
            )}
          </Row>
          <Row label="Price timestamp">
            {formatUtc(oracle.updatedAt)} <span className="dim">({formatAge(oracle.ageSeconds)})</span>
          </Row>
          <Row label="Market session">
            {oracle.error ? (
              <Badge tone="warn">UNKNOWN</Badge>
            ) : (
              <Badge tone={marketClosed ? "warn" : "good"}>{marketClosed ? "CLOSED" : "OPEN"}</Badge>
            )}{" "}
            <span className="dim">
              tokenized equity, {oracleConfig.marketHours.replace(/_/g, " ")}
            </span>
          </Row>
          <OracleStatePanel reading={oracle} />
          <Row label="State source">
            {oracle.source === "oracle-guard" ? (
              <>
                <Badge tone="good">ORACLEGUARD</Badge>{" "}
                <span className="dim">state returned by the deployed guard</span>
              </>
            ) : (
              <>
                <Badge tone="warn">DIRECT FEED</Badge>{" "}
                <span className="dim">
                  guard not yet deployed; state derived from a direct read of the official proxy
                </span>
              </>
            )}
          </Row>
          <Row label="Feed decimals">
            {oracle.feedDecimals ?? oracleConfig.decimals}{" "}
            <span className="dim">read from the feed, never assumed</span>
          </Row>
          <Row label="Heartbeat">
            {oracleConfig.heartbeatSeconds.toLocaleString()}s{" "}
            <span className="dim">
              deviation {oracleConfig.deviationThresholdPercent}%; no heartbeat while the market is
              closed
            </span>
          </Row>
          <Row label="Freshness policy">
            <span className="mono">
              {oracleConfig.maxStalenessSeconds.toLocaleString()}s open /{" "}
              {oracleConfig.maxHeldStalenessSeconds.toLocaleString()}s closed
            </span>
          </Row>
          <Row label="Corporate-action pause">
            {oracle.oraclePaused === null ? (
              <span className="dim">reported by the guard</span>
            ) : (
              <>
                <Badge tone={oracle.oraclePaused ? "warn" : "good"}>
                  {oracle.oraclePaused ? "PAUSED" : "NOT PAUSED"}
                </Badge>{" "}
                <span className="dim">advisory only, not enforced onchain</span>
              </>
            )}
          </Row>
          <Row label="Sequencer uptime feed">
            <NotConfigured reason="no feed published for this network; checks are skipped" />
          </Row>
        </dl>
      </section>

      <section aria-labelledby="contracts-heading">
        <h2 id="contracts-heading">Contracts and network</h2>
        <dl className="rows">
          <Row label="Network">
            {chainConfig.name} <span className="dim">chain ID {chainConfig.id}, gas token ETH</span>
          </Row>
          <Row label="Chain head">
            {head ? (
              <>
                <span className="mono">block {head.blockNumber.toString()}</span>{" "}
                <Badge tone="good">LIVE READ</Badge>
              </>
            ) : (
              <span className="dim">RPC unreachable</span>
            )}
          </Row>
          <Row label="ProjectHomeRegistry">
            {registryAddress ? (
              <AddressLink address={registryAddress} />
            ) : (
              <NotConfigured reason="deployment gated on gas approval" />
            )}
          </Row>
          <Row label="OracleGuard">
            {guardAddress ? (
              <AddressLink address={guardAddress} />
            ) : (
              <NotConfigured reason="deployment gated on gas approval" />
            )}
          </Row>
          {chainConfig.isRehearsal ? (
            <Row label="Chainlink feed">
              <NotConfigured reason="published on mainnet only; the rehearsal guard reads a mock" />
            </Row>
          ) : (
            <>
              <Row label="Chainlink feed proxy">
                <AddressLink address={oracleConfig.feedProxy} />
              </Row>
              <Row label="Chainlink aggregator">
                <AddressLink address={oracleConfig.aggregator} />
              </Row>
              <Row label="Stock Token ERC-20">
                <AddressLink address={oracleConfig.stockToken} />
              </Row>
            </>
          )}
          <Row label="Explorer">
            <a href={chainConfig.explorer} rel="noreferrer noopener" target="_blank">
              {chainConfig.explorer.replace("https://", "")}
            </a>
          </Row>
        </dl>
      </section>

      <footer>
        <ul>
          <li>
            <a href={projectConfig.repository} rel="noreferrer noopener" target="_blank">
              GitHub
            </a>
          </li>
          <li>
            <a href={projectConfig.website} rel="noreferrer noopener" target="_blank">
              metacade.co
            </a>
          </li>
          <li>
            <a href={projectConfig.x} rel="noreferrer noopener" target="_blank">
              X
            </a>
          </li>
          <li>
            <a href={projectConfig.linkedin} rel="noreferrer noopener" target="_blank">
              LinkedIn
            </a>
          </li>
          {chainConfig.isRehearsal ? null : (
            <li>
              <a
                href={explorerAddressUrl(oracleConfig.feedProxy)}
                rel="noreferrer noopener"
                target="_blank"
              >
                Feed on Blockscout
              </a>
            </li>
          )}
        </ul>
        <p>
          Read-only reference implementation. No wallet connection, no authentication, no private
          API. The price, its timestamp, the oracle state and the chain head are live reads of
          {chainConfig.isRehearsal ? chainConfig.name : "Robinhood Chain mainnet"}. The heartbeat, deviation threshold, freshness policy, market
          hours and progression rows are configuration, shown so the live values can be judged
          against them.
        </p>
      </footer>
    </main>
  );
}
