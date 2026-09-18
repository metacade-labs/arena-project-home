import {createPublicClient, defineChain, http, formatUnits, type Address} from "viem";
import {
  aggregatorV3Abi,
  oracleGuardAbi,
  projectHomeRegistryAbi,
  stockTokenAbi
} from "./abi";
import {
  ORACLE_STATES,
  chainConfig,
  deployedContracts,
  oracleConfig,
  type OracleStateName
} from "./config";

export const robinhoodChain = defineChain({
  id: chainConfig.id,
  name: chainConfig.name,
  nativeCurrency: chainConfig.nativeCurrency,
  rpcUrls: {default: {http: [chainConfig.rpcUrl]}},
  blockExplorers: {default: {name: "Blockscout", url: chainConfig.explorer}}
});

export const publicClient = createPublicClient({
  chain: robinhoodChain,
  transport: http(chainConfig.rpcUrl, {timeout: 15_000, retryCount: 2})
});

export type OracleReading = {
  /** Where the state came from: the deployed guard, or a direct feed read. */
  source: "oracle-guard" | "direct-feed";
  state: OracleStateName;
  /** Human price string, already scaled by the feed's own decimals. */
  price: string | null;
  rawAnswer: bigint | null;
  feedDecimals: number | null;
  updatedAt: number | null;
  ageSeconds: number | null;
  marketClosed: boolean;
  oraclePaused: boolean | null;
  error: string | null;
};

export type ProjectReading = {
  id: bigint;
  slug: string;
  displayName: string;
  owner: Address;
  metadataURI: string;
  homeChainId: bigint;
  treasury: Address;
  active: boolean;
  createdAt: number;
  updatedAt: number;
};

/** Weekly closure of a 24/5 US-equity session, mirroring OracleGuard.isMarketClosed. */
export const isMarketClosedUtc = (unixSeconds: number): boolean => {
  const dayOfWeek = (Math.floor(unixSeconds / 86_400) + 4) % 7; // 0 = Sunday
  return dayOfWeek === 0 || dayOfWeek === 6;
};

/**
 * Reads the deployed OracleGuard when it exists. Before deployment, falls back to a
 * direct read of the official Chainlink proxy so the page still shows live chain data,
 * clearly labelled as coming from the feed rather than from the guard.
 */
export async function readOracle(): Promise<OracleReading> {
  const guard = deployedContracts.oracleGuard;

  if (guard) {
    try {
      const status = await publicClient.readContract({
        address: guard,
        abi: oracleGuardAbi,
        functionName: "checkPrice",
        args: [oracleConfig.symbol]
      });

      const s = status as unknown as {
        state: number;
        answer: bigint;
        feedDecimals: number;
        updatedAt: bigint;
        age: bigint;
        marketClosed: boolean;
      };

      return {
        source: "oracle-guard",
        state: ORACLE_STATES[s.state] ?? "UNSUPPORTED",
        price:
          s.answer > 0n ? formatUnits(s.answer, Number(s.feedDecimals) || oracleConfig.decimals) : null,
        rawAnswer: s.answer,
        feedDecimals: Number(s.feedDecimals),
        updatedAt: Number(s.updatedAt),
        ageSeconds: Number(s.age),
        marketClosed: s.marketClosed,
        oraclePaused: null,
        error: null
      };
    } catch (error) {
      return emptyReading("oracle-guard", messageOf(error));
    }
  }

  // Guard not yet deployed: read the official feed directly.
  try {
    const [decimals, round, paused] = await Promise.all([
      publicClient.readContract({
        address: oracleConfig.feedProxy,
        abi: aggregatorV3Abi,
        functionName: "decimals"
      }),
      publicClient.readContract({
        address: oracleConfig.feedProxy,
        abi: aggregatorV3Abi,
        functionName: "latestRoundData"
      }),
      publicClient
        .readContract({
          address: oracleConfig.stockToken,
          abi: stockTokenAbi,
          functionName: "oraclePaused"
        })
        .catch(() => null)
    ]);

    const [, answer, , updatedAt] = round as readonly [bigint, bigint, bigint, bigint, bigint];
    const feedDecimals = Number(decimals);
    const now = Math.floor(Date.now() / 1000);
    const updated = Number(updatedAt);
    const age = updated > 0 ? now - updated : null;
    const marketClosed = isMarketClosedUtc(now);

    return {
      source: "direct-feed",
      state: deriveDirectState({answer, updated, age, marketClosed, paused: paused as boolean | null}),
      price: answer > 0n ? formatUnits(answer, feedDecimals) : null,
      rawAnswer: answer,
      feedDecimals,
      updatedAt: updated,
      ageSeconds: age,
      marketClosed,
      oraclePaused: paused as boolean | null,
      error: null
    };
  } catch (error) {
    return emptyReading("direct-feed", messageOf(error));
  }
}

/**
 * Mirrors the guard's precedence for the pre-deployment view: answer sanity, then
 * freshness gated on market session, then the advisory pause flag. The sequencer
 * branch is absent here because no sequencer feed is published for this network.
 */
function deriveDirectState(input: {
  answer: bigint;
  updated: number;
  age: number | null;
  marketClosed: boolean;
  paused: boolean | null;
}): OracleStateName {
  const {answer, updated, age, marketClosed, paused} = input;
  if (answer <= 0n || updated === 0 || age === null || age < 0) return "INVALID_ANSWER";
  const bound = marketClosed ? oracleConfig.maxHeldStalenessSeconds : oracleConfig.maxStalenessSeconds;
  if (age > bound) return "STALE";
  if (paused === true) return "ORACLE_PAUSED";
  return "VALID";
}

export async function readProject(): Promise<ProjectReading | null> {
  const registry = deployedContracts.projectHomeRegistry;
  if (!registry) return null;

  try {
    const project = await publicClient.readContract({
      address: registry,
      abi: projectHomeRegistryAbi,
      functionName: "getProjectBySlug",
      args: ["metacade"]
    });

    const p = project as unknown as ProjectReading & {
      createdAt: bigint;
      updatedAt: bigint;
    };

    return {
      ...p,
      createdAt: Number(p.createdAt),
      updatedAt: Number(p.updatedAt)
    };
  } catch {
    return null;
  }
}

/** Proves the page reached the chain, independent of any contract read. */
export async function readChainHead(): Promise<{blockNumber: bigint; chainId: number} | null> {
  try {
    const [blockNumber, chainId] = await Promise.all([
      publicClient.getBlockNumber(),
      publicClient.getChainId()
    ]);
    return {blockNumber, chainId};
  } catch {
    return null;
  }
}

const emptyReading = (source: OracleReading["source"], error: string): OracleReading => ({
  source,
  state: "UNSUPPORTED",
  price: null,
  rawAnswer: null,
  feedDecimals: null,
  updatedAt: null,
  ageSeconds: null,
  marketClosed: false,
  oraclePaused: null,
  error
});

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message.split("\n")[0] : "Unknown read error";
