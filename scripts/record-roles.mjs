// Records the post-handoff role state of the deployed pair, read from the chain.
//
//   node scripts/record-roles.mjs <chainId> <newAdmin>
//
// Reads the contract addresses and deployer from the deployment file for that chain,
// then calls hasRole for all five roles, for the deployer and for the new admin, pinned
// to a single block so the ten reads describe one moment. Writes the result under
// "roleHandoff" in the same file. Exits non-zero, writing nothing, unless every read
// shows the deployer without the role and the new admin with it.
//
// If forge's broadcast of HandoffRoles.s.sol for this chain exists, its ten transaction
// hashes are recorded too, each re-fetched from the network first so that a local fork
// run can never be recorded.
//
// Uses the local `cast` binary for the reads; no new dependency.
import {execFileSync} from "node:child_process";
import {existsSync, readFileSync, writeFileSync} from "node:fs";

const FILES = {
  46630: {file: "deployments/robinhood-chain-testnet.json", rpc: "https://rpc.testnet.chain.robinhood.com"},
  4663: {file: "deployments/robinhood-chain.json", rpc: "https://rpc.mainnet.chain.robinhood.com"}
};

const chainId = Number(process.argv[2]);
const newAdmin = process.argv[3];
const target = FILES[chainId];
if (!target) {
  console.error(`No deployment record is defined for chain ${process.argv[2]}.`);
  process.exit(1);
}
if (!/^0x[0-9a-fA-F]{40}$/.test(newAdmin ?? "")) {
  console.error("Usage: node scripts/record-roles.mjs <chainId> <newAdmin>");
  process.exit(1);
}

const record = JSON.parse(readFileSync(target.file, "utf8"));
const {ProjectHomeRegistry: registry, OracleGuard: guard} = record.contracts ?? {};
if (record.status !== "DEPLOYED" || !registry || !guard || !record.deployer) {
  console.error(`${target.file} does not record a deployment yet.`);
  process.exit(1);
}

const cast = (...args) =>
  execFileSync("cast", [...args, "--rpc-url", target.rpc], {encoding: "utf8"}).trim();

if (Number(cast("chain-id")) !== chainId) {
  console.error(`RPC ${target.rpc} does not report chain ${chainId}.`);
  process.exit(1);
}
const block = cast("block-number");
const timestamp = Number(cast("block", block, "--field", "timestamp"));

const roleId = (contract, name) => cast("call", contract, `${name}()(bytes32)`, "--block", block);
const hasRole = (contract, role, account) =>
  cast("call", contract, "hasRole(bytes32,address)(bool)", role, account, "--block", block) === "true";

const ROLES = [
  ["ProjectHomeRegistry", registry, "DEFAULT_ADMIN_ROLE"],
  ["ProjectHomeRegistry", registry, "REGISTRAR_ROLE"],
  ["ProjectHomeRegistry", registry, "CURATOR_ROLE"],
  ["OracleGuard", guard, "DEFAULT_ADMIN_ROLE"],
  ["OracleGuard", guard, "ASSET_MANAGER_ROLE"]
];

const reads = ROLES.map(([contract, address, name]) => {
  const role = roleId(address, name);
  return {
    contract,
    role: name,
    deployer: hasRole(address, role, record.deployer),
    newAdmin: hasRole(address, role, newAdmin)
  };
});

const owner = cast(
  "call",
  registry,
  "getProjectBySlug(string)((uint256,string,string,address,string,uint256,address,bool,uint64,uint64))",
  "metacade",
  "--block",
  block
).match(/0x[0-9a-fA-F]{40}/)[0];

for (const r of reads) console.log(`${r.contract}.${r.role}  deployer=${r.deployer}  newAdmin=${r.newAdmin}`);
console.log(`project owner ${owner}`);

const complete =
  reads.every((r) => r.deployer === false && r.newAdmin === true) &&
  owner.toLowerCase() === newAdmin.toLowerCase();
if (!complete) {
  console.error("Handoff is not complete at this block. Nothing written.");
  process.exit(1);
}

let transactions = null;
const runPath = `broadcast/HandoffRoles.s.sol/${chainId}/run-latest.json`;
if (existsSync(runPath)) {
  const run = JSON.parse(readFileSync(runPath, "utf8"));
  transactions = run.transactions.map((tx) => {
    let live;
    try {
      live = JSON.parse(cast("receipt", tx.hash, "--async", "--json"));
    } catch {
      console.error(`${tx.hash} is not on chain ${chainId}. Refusing to record a local or fork run.`);
      process.exit(1);
    }
    if (live.status !== "0x1") {
      console.error(`${tx.hash} did not succeed.`);
      process.exit(1);
    }
    return {
      function: tx.function,
      to: tx.transaction.to,
      txHash: tx.hash,
      blockNumber: Number(BigInt(live.blockNumber)),
      gasUsed: Number(BigInt(live.gasUsed))
    };
  });
}

record.roleHandoff = {
  newAdmin,
  deployer: record.deployer,
  projectOwner: owner,
  readAtBlock: Number(block),
  readAtUtc: new Date(timestamp * 1000).toISOString(),
  reads,
  transactions
};
writeFileSync(target.file, JSON.stringify(record, null, 2) + "\n");
console.log(`Recorded role handoff at block ${block} to ${target.file}`);
