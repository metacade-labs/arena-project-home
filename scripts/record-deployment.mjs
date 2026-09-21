// Records a broadcast Deploy.s.sol run into the deployment file for its chain.
//
//   node scripts/record-deployment.mjs <chainId>
//
// Reads broadcast/Deploy.s.sol/<chainId>/run-latest.json, which forge writes only on a
// real broadcast, and takes every address and transaction hash from it and its
// receipts. Nothing is typed in by hand.
//
// The chain id selects the output file and nothing else can. A testnet run writes
// deployments/robinhood-chain-testnet.json and has no path to the mainnet record.
//
// Every receipt is re-fetched from the network's public RPC before anything is written.
// A local fork (anvil) reports the same chain id and forge files its runs under the same
// path, so the broadcast file alone cannot prove a transaction reached the real chain.
import {execFileSync} from "node:child_process";
import {existsSync, readFileSync, writeFileSync} from "node:fs";

const TARGETS = {
  46630: {
    file: "deployments/robinhood-chain-testnet.json",
    network: "Robinhood Chain Testnet",
    rpcUrl: "https://rpc.testnet.chain.robinhood.com",
    explorer: "https://explorer.testnet.chain.robinhood.com",
    note:
      "Rehearsal only. The guard reads a MockAggregator deployed by the same script, because " +
      "Chainlink publishes no Robinhood feed on testnet. Nothing here is a price source, and " +
      "no address in this file belongs in the submission pack.",
    contracts: ["MockAggregator", "ProjectHomeRegistry", "OracleGuard"]
  },
  4663: {
    file: "deployments/robinhood-chain.json",
    network: "Robinhood Chain Mainnet",
    rpcUrl: "https://rpc.mainnet.chain.robinhood.com",
    explorer: "https://robinhoodchain.blockscout.com",
    note: null,
    contracts: ["ProjectHomeRegistry", "OracleGuard"]
  }
};

const chainId = Number(process.argv[2]);
const target = TARGETS[chainId];
if (!target) {
  console.error(`No deployment record is defined for chain ${process.argv[2]}.`);
  process.exit(1);
}

const runPath = `broadcast/Deploy.s.sol/${chainId}/run-latest.json`;
if (!existsSync(runPath)) {
  console.error(`${runPath} not found. It is written only by a real --broadcast run.`);
  process.exit(1);
}
const run = JSON.parse(readFileSync(runPath, "utf8"));

if (Number(run.chain) !== chainId) {
  console.error(`${runPath} is for chain ${run.chain}, not ${chainId}.`);
  process.exit(1);
}
if (!Array.isArray(run.receipts) || run.receipts.length !== run.transactions.length) {
  console.error("Receipts are missing or incomplete. Refusing to record an unconfirmed run.");
  process.exit(1);
}

const cast = (...args) =>
  execFileSync("cast", [...args, "--rpc-url", target.rpcUrl], {encoding: "utf8"}).trim();
if (Number(cast("chain-id")) !== chainId) {
  console.error(`${target.rpcUrl} does not report chain ${chainId}.`);
  process.exit(1);
}
for (const r of run.receipts) {
  let live;
  try {
    live = JSON.parse(cast("receipt", r.transactionHash, "--async", "--json"));
  } catch {
    console.error(`${r.transactionHash} is not on ${target.network}. Refusing to record a local or fork run.`);
    process.exit(1);
  }
  const same =
    live.status === r.status &&
    BigInt(live.blockNumber) === BigInt(r.blockNumber) &&
    (live.contractAddress ?? null)?.toLowerCase() === (r.contractAddress ?? null)?.toLowerCase();
  if (!same) {
    console.error(`${r.transactionHash} on ${target.network} does not match the broadcast file.`);
    process.exit(1);
  }
}

const receiptByHash = new Map(run.receipts.map((r) => [r.transactionHash.toLowerCase(), r]));
const transactions = run.transactions.map((tx) => {
  const receipt = receiptByHash.get(tx.hash.toLowerCase());
  if (!receipt) throw new Error(`No receipt for ${tx.hash}`);
  if (receipt.status !== "0x1") throw new Error(`Transaction ${tx.hash} did not succeed`);
  return {
    type: tx.transactionType,
    contract: tx.contractName,
    function: tx.function ?? null,
    contractAddress: tx.transactionType === "CREATE" ? tx.contractAddress : null,
    txHash: tx.hash,
    blockNumber: Number(BigInt(receipt.blockNumber)),
    gasUsed: Number(BigInt(receipt.gasUsed))
  };
});

const created = transactions.filter((t) => t.type === "CREATE");
const createdNames = created.map((t) => t.contract).sort();
if (JSON.stringify(createdNames) !== JSON.stringify([...target.contracts].sort())) {
  console.error(
    `Expected creates ${JSON.stringify(target.contracts)} on chain ${chainId}, found ${JSON.stringify(createdNames)}.`
  );
  process.exit(1);
}

const contracts = {};
const deploymentTxHashes = {};
for (const t of created) {
  contracts[t.contract] = t.contractAddress;
  deploymentTxHashes[t.contract] = t.txHash;
}

const existing = existsSync(target.file) ? JSON.parse(readFileSync(target.file, "utf8")) : {};
const record = {
  ...existing,
  network: target.network,
  chainId,
  rpcUrl: target.rpcUrl,
  explorer: target.explorer,
  status: "DEPLOYED",
  note: target.note ?? existing.note ?? null,
  deployer: run.transactions[0].transaction.from,
  contracts,
  deploymentTxHashes,
  transactions,
  recordedFrom: runPath
};
if (target.note === null) delete record.note;

writeFileSync(target.file, JSON.stringify(record, null, 2) + "\n");
console.log(`Recorded ${created.length} contracts on chain ${chainId} to ${target.file}`);
