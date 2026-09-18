import type {OracleReading} from "../lib/chain";
import type {OracleStateName} from "../lib/config";
import {Badge, type BadgeTone} from "./Primitives";

const TONES: Record<OracleStateName, BadgeTone> = {
  VALID: "good",
  UNSUPPORTED: "warn",
  STALE: "bad",
  SEQUENCER_DOWN: "bad",
  GRACE_PERIOD: "warn",
  ORACLE_PAUSED: "warn",
  INVALID_ANSWER: "bad"
};

const EXPLANATIONS: Record<OracleStateName, string> = {
  VALID: "The feed answered, the answer is positive and it is within the freshness bound for the current session.",
  UNSUPPORTED: "No official feed is configured for this asset, so it has no validated price.",
  STALE: "The last published price is older than the bound for the current session. Do not treat it as current.",
  SEQUENCER_DOWN: "The L2 sequencer is reported down. Feed values cannot be trusted while it is.",
  GRACE_PERIOD: "The sequencer has recently come back up. Values are withheld until the grace period elapses.",
  ORACLE_PAUSED: "Publishing is paused for a corporate action. This flag is advisory and is not enforced onchain.",
  INVALID_ANSWER: "The feed returned a non-positive answer, an unset round or no usable timestamp."
};

export function OracleStatePanel({reading}: {reading: OracleReading}) {
  const {state, marketClosed} = reading;
  const heldPrice = state === "VALID" && marketClosed;

  return (
    <>
      <div className="row">
        <dt>Oracle state</dt>
        <dd>
          <Badge tone={TONES[state]}>{state}</Badge>
          {heldPrice ? (
            <>
              {" "}
              <Badge tone="warn">MARKET CLOSED</Badge>
            </>
          ) : null}
          <p className="dim" style={{margin: "0.4rem 0 0", fontSize: "0.87rem"}}>
            {EXPLANATIONS[state]}
          </p>
        </dd>
      </div>

      {heldPrice ? (
        <div className="callout">
          <strong>This is a held price, not a live one.</strong> Tokenized equity feeds trade 24/5
          and publish no heartbeat while the underlying market is closed, so the feed holds its last
          published price and remains callable. The guard reports this as VALID because the feed is
          healthy, and the market-closed annotation is the only thing separating it from a live
          price. This page displays the price and never converts or settles against it.
        </div>
      ) : null}

      {reading.error ? (
        <div className="callout">
          <strong>Read failed.</strong> <span className="mono">{reading.error}</span>
        </div>
      ) : null}
    </>
  );
}
