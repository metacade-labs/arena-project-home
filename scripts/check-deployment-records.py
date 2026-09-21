"""Deployment records may hold 64-hex values only as transaction hashes.

CI's blanket key-material check exempts deployments/, because transaction hashes are
64-hex by nature. This replaces it there with a stricter rule: a 64-hex value is allowed
only as the whole value of a key ending in "Hash", or of an entry inside an object whose
key ends in "Hashes". Anything else fails, as does any 64-hex in a non-JSON file.

    python3 scripts/check-deployment-records.py [root]
"""

import glob
import json
import os
import re
import sys

HEX64 = re.compile(r"(0x)?[a-fA-F0-9]{64}")


def walk(node, path, key, parent, bad):
    if isinstance(node, dict):
        for k, v in node.items():
            walk(v, f"{path}.{k}", k, key, bad)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]", key, parent, bad)
    elif isinstance(node, str) and HEX64.search(node):
        allowed = key.endswith("Hash") or parent.endswith("Hashes")
        if not (allowed and HEX64.fullmatch(node)):
            bad.append(path)


def main(root):
    bad = []
    for f in sorted(glob.glob(os.path.join(root, "deployments", "**", "*"), recursive=True)):
        if not os.path.isfile(f):
            continue
        if f.endswith(".json"):
            with open(f) as fh:
                walk(json.load(fh), f, "", "", bad)
        else:
            with open(f, errors="ignore") as fh:
                if HEX64.search(fh.read()):
                    bad.append(f)
    if bad:
        print("64-hex values outside a transaction-hash field:", *bad, sep="\n  ")
        return 1
    print("Deployment records clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
