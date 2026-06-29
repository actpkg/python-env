#!/usr/bin/env bash
# Build all sci wheels and a full PEP 503 index.
# Reads the [dependency-groups].sci list from pyproject.toml, orders numpy
# before pandas/bottleneck (they build against numpy headers), then builds
# each lib via build-wheel.sh.  After all wheels are built, generates the
# full simple/ index under dist/_site with file:// hrefs.
#
# Run inside python-env-toolchain:latest:
#   docker run --rm -v "$PWD/components/python-env:/work" -w /work \
#     python-env-toolchain:latest bash sci/wheels/build-all.sh
#
# Output:
#   /work/dist/<lib>-<ver>-cp314-cp314-wasi_0_0_0_wasm32.whl  (8 wheels)
#   /work/dist/_site/simple/                                   (PEP 503 index)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYPROJECT="$SCRIPT_DIR/../../pyproject.toml"

# ── Parse sci lib names from pyproject.toml ──────────────────────────────────
# Extracts package names (without version constraints), normalised to lowercase.
RAW_LIBS=$(python3 - "$PYPROJECT" <<'PY'
import sys, tomllib, re
with open(sys.argv[1], "rb") as f:
    d = tomllib.load(f)
sci = d["dependency-groups"]["sci"]
names = [re.split(r"[>=<!~\s]", s)[0].strip() for s in sci]
# normalise to lowercase (Pillow -> pillow, etc.)
print("\n".join(n.lower() for n in names))
PY
)

# ── Impose build order: numpy first, then remaining libs ─────────────────────
# pandas and bottleneck must see numpy's compiled headers, so numpy goes first.
ALL_LIBS=()
REMAINING=()
while IFS= read -r lib; do
    if [ "$lib" = "numpy" ]; then
        ALL_LIBS+=("$lib")
    else
        REMAINING+=("$lib")
    fi
done <<< "$RAW_LIBS"
ALL_LIBS+=("${REMAINING[@]}")

echo "### build-all: libs to build (in order): ${ALL_LIBS[*]}"

# ── Build each lib ────────────────────────────────────────────────────────────
FAILED=()
for lib in "${ALL_LIBS[@]}"; do
    echo ""
    echo "##############################################################"
    echo "### [$(date -u +%H:%M:%S)] Starting build: $lib"
    echo "##############################################################"
    if bash "$SCRIPT_DIR/build-wheel.sh" "$lib"; then
        echo "### [$(date -u +%H:%M:%S)] DONE: $lib"
    else
        echo "### [$(date -u +%H:%M:%S)] FAILED: $lib" >&2
        FAILED+=("$lib")
    fi
done

# ── Report failures before index step ────────────────────────────────────────
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "### ERROR: ${#FAILED[@]} lib(s) failed: ${FAILED[*]}" >&2
    exit 1
fi

# ── Generate the full PEP 503 index ──────────────────────────────────────────
DIST_DIR="$SCRIPT_DIR/../../dist"
SITE_DIR="$DIST_DIR/_site"
BASE_URL="file://$DIST_DIR"

echo ""
echo "### [$(date -u +%H:%M:%S)] Generating PEP 503 index -> $SITE_DIR"
bash "$SCRIPT_DIR/index/build-index.sh" "$DIST_DIR" "$SITE_DIR" "$BASE_URL"
echo "### [$(date -u +%H:%M:%S)] Index done: $SITE_DIR/simple/"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "### build-all complete"
echo "### Wheels built (${#ALL_LIBS[@]}):"
ls "$DIST_DIR"/*-cp314-cp314-wasi_0_0_0_wasm32.whl 2>/dev/null \
    | while read -r w; do echo "    $(basename "$w")"; done
echo "### Index: $SITE_DIR/simple/"
