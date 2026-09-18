import type {ReactNode} from "react";
import {explorerAddressUrl} from "../lib/config";

export function Row({label, children}: {label: string; children: ReactNode}) {
  return (
    <div className="row">
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

export type BadgeTone = "good" | "warn" | "bad" | "neutral";

export function Badge({tone, children}: {tone: BadgeTone; children: ReactNode}) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

/** LIVE, BUILT and FUTURE are the only three maturity labels used on this page. */
export function StateLabel({state}: {state: "LIVE" | "BUILT" | "FUTURE"}) {
  const tone: BadgeTone = state === "LIVE" ? "good" : state === "BUILT" ? "neutral" : "warn";
  return <Badge tone={tone}>{state}</Badge>;
}

export function AddressLink({address, label}: {address: string; label?: string}) {
  return (
    <a className="mono" href={explorerAddressUrl(address)} rel="noreferrer noopener" target="_blank">
      {label ?? address}
    </a>
  );
}

export function NotConfigured({reason}: {reason?: string}) {
  return (
    <>
      <Badge tone="warn">NOT CONFIGURED</Badge>
      {reason ? <span className="dim"> {reason}</span> : null}
    </>
  );
}

export function formatUtc(unixSeconds: number | null): string {
  if (!unixSeconds) return "unavailable";
  return `${new Date(unixSeconds * 1000).toISOString().replace("T", " ").slice(0, 19)} UTC`;
}

export function formatAge(seconds: number | null): string {
  if (seconds === null) return "unavailable";
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86_400) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m ago`;
  return `${Math.floor(seconds / 86_400)}d ${Math.floor((seconds % 86_400) / 3600)}h ago`;
}
