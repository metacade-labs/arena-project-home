import type {Address} from "viem";

/**
 * Public chain configuration. Everything here is public by construction: official
 * contract addresses, a public RPC and a chain id. No secret belongs in this file
 * or in any NEXT_PUBLIC_ variable.
 */

const asAddress = (value: string | undefined): Address | null => {
  if (!value) return null;
  const trimmed = value.trim();
  return /^0x[a-fA-F0-9]{40}$/.test(trimmed) ? (trimmed as Address) : null;
};

/**
 * Networks. Source: docs.robinhood.com/chain/connecting
 *
 * Mainnet is the default and the only network the public deployment uses. The testnet
 * entry exists so the deploy rehearsal can prove the page's read path against real
 * contracts; there the guard reads a mock feed, so the page marks itself as a rehearsal.
 */
const networks = {
  4663: {
    id: 4663,
    name: "Robinhood Chain",
    rpcUrl: process.env.ROBINHOOD_RPC_URL ?? "https://rpc.mainnet.chain.robinhood.com",
    explorer: "https://robinhoodchain.blockscout.com",
    nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
    isRehearsal: false
  },
  46630: {
    id: 46630,
    name: "Robinhood Chain Testnet",
    rpcUrl: process.env.ROBINHOOD_TESTNET_RPC_URL ?? "https://rpc.testnet.chain.robinhood.com",
    explorer: "https://explorer.testnet.chain.robinhood.com",
    nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
    isRehearsal: true
  }
} as const;

const selectNetwork = (value: string | undefined) => {
  const id = value?.trim() || "4663";
  if (id !== "4663" && id !== "46630") {
    // An unknown chain is a misconfiguration, not a reason to quietly show mainnet.
    throw new Error(`ROBINHOOD_CHAIN_ID must be 4663 or 46630, got "${id}"`);
  }
  return networks[Number(id) as keyof typeof networks];
};

export const chainConfig = selectNetwork(process.env.ROBINHOOD_CHAIN_ID);

/**
 * Deployed reference contracts. Null until the deployment gate is cleared, which the
 * page renders explicitly rather than hiding.
 */
export const deployedContracts = {
  projectHomeRegistry: asAddress(process.env.NEXT_PUBLIC_REGISTRY_ADDRESS),
  oracleGuard: asAddress(process.env.NEXT_PUBLIC_ORACLE_GUARD_ADDRESS)
};

/**
 * Official Chainlink feed on Robinhood Chain mainnet.
 * Source: Chainlink Data Feeds directory, Robinhood Chain mainnet.
 * The Stock Token address is from Robinhood's official asset registry, chainId 4663.
 */
export const oracleConfig = {
  symbol: "NVDA",
  feedName: "Robinhood NVDA / USD",
  assetName: "Nvidia (Robinhood Tokenized Equity)",
  feedProxy: "0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15" as Address,
  aggregator: "0xC9d16E4f2569b9E3ea0468fD85844953713DC2a2" as Address,
  stockToken: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC" as Address,
  decimals: 8,
  heartbeatSeconds: 86_400,
  deviationThresholdPercent: 0.5,
  marketHours: "us_equities_24/5",
  maxStalenessSeconds: 90_000,
  maxHeldStalenessSeconds: 432_000,
  sequencerUptimeFeed: null as Address | null,
  sequencerGracePeriodSeconds: 3_600
} as const;

export const projectConfig = {
  slug: "metacade",
  displayName: "Metacade",
  summary:
    "Social influence fighting game powered by agents. This Project Home is a public reference implementation; the wider Arena is not live on Robinhood Chain.",
  arenaZone: "City Gates",
  nextProgression: "Community Diagnostic",
  repository: "https://github.com/metacade-labs/arena-project-home",
  website: "https://metacade.co",
  x: "https://x.com/Metacade_",
  linkedin: "https://www.linkedin.com/company/metacade"
} as const;

/** Mirrors OracleGuard.OracleState. UNSUPPORTED is index 0 by design. */
export const ORACLE_STATES = [
  "UNSUPPORTED",
  "VALID",
  "STALE",
  "SEQUENCER_DOWN",
  "GRACE_PERIOD",
  "ORACLE_PAUSED",
  "INVALID_ANSWER"
] as const;

export type OracleStateName = (typeof ORACLE_STATES)[number];

export const explorerAddressUrl = (address: string) =>
  `${chainConfig.explorer}/address/${address}`;
