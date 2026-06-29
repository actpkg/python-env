#!/usr/bin/env bash
# End-to-end smoke test: fold a trivial Python component that imports sqlite3 (a C-ext).
# Runs INSIDE python-env-toolchain:latest.
# Usage (from repo root, mounting the component dir):
#   docker run --rm -v "$PWD:/work" -w /work python-env-toolchain:latest bash sci/smoke/run-smoke.sh
set -xeuo pipefail

WIT=/work/sci/smoke/world.wit
OUTPUT=/work/sci/smoke/smoke.wasm

# Fold the component: sqlite3 is a CPython C-ext; folding it exercises the full toolchain.
componentize-py \
  -d "${WIT}" \
  -w smoke \
  componentize \
  -p /work/sci/smoke \
  smoke_app \
  -o "${OUTPUT}"

# Assert: output file is non-empty
test -s "${OUTPUT}"
echo "smoke.wasm size: $(stat -c '%s' "${OUTPUT}") bytes"

# Validate with wasm-tools if available
if command -v wasm-tools &>/dev/null; then
  wasm-tools validate "${OUTPUT}"
  echo "wasm-tools validate: OK"
else
  echo "wasm-tools not in PATH — skipping validate"
fi

echo "SMOKE FOLD OK"
