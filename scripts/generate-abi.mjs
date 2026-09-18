// Regenerates apps/web/lib/abi.ts from the compiled Foundry artifacts.
import {readFileSync, writeFileSync} from "node:fs";

const read = (p) => JSON.parse(readFileSync(p, "utf8")).abi;

const registry = read("contracts/out/ProjectHomeRegistry.sol/ProjectHomeRegistry.json");
const guard = read("contracts/out/OracleGuard.sol/OracleGuard.json");
const existing = readFileSync("apps/web/lib/abi.ts", "utf8");

// The aggregator and stock-token ABIs are hand-maintained minimal read surfaces and
// are preserved verbatim; only the two project contracts are regenerated.
const tail = existing.slice(existing.indexOf("export const aggregatorV3Abi"));

const header =
  "// Generated from the compiled Foundry artifacts. Do not hand-edit.\n" +
  "// Regenerate with: forge build && node scripts/generate-abi.mjs\n\n";

writeFileSync(
  "apps/web/lib/abi.ts",
  header +
    `export const projectHomeRegistryAbi = ${JSON.stringify(registry, null, 2)} as const;\n\n` +
    `export const oracleGuardAbi = ${JSON.stringify(guard, null, 2)} as const;\n\n` +
    tail
);
console.log("apps/web/lib/abi.ts regenerated");
