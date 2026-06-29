#!/usr/bin/env bash
# bake-sci.sh — runs INSIDE python-env-toolchain:latest (component dir at /work)
# Builds a PEP 503 index from pre-built wasm wheels, cross-installs the sci group,
# regenerates the app.py sci-import block, then folds → /work/python-env.wasm.
set -xeuo pipefail

WHEEL_DIR="${WHEEL_DIR:-/work/dist}"

# Install sci wheels to /tmp/sci-pkgs (outside /work) so that '-p .' used in the fold
# step does not pick them up a second time as a subdirectory of the component tree.
SCI_PKGS=/tmp/sci-pkgs

# Clean up any leftover sci-pkgs directory inside /work from previous runs (old layout).
rm -rf /work/sci-pkgs

# 1. Build a local PEP 503 index from the wasm wheels.
IDX=$(mktemp -d)
bash /work/sci/wheels/index/build-index.sh "$WHEEL_DIR" "$IDX" "file://$WHEEL_DIR"

# 2. Read the sci lib names from pyproject.toml.
LIBS=$(python3 - <<'PY'
import tomllib, re
d = tomllib.load(open("/work/pyproject.toml", "rb"))
print(" ".join(re.split(r"[>=<!~ ]", s)[0] for s in d["dependency-groups"]["sci"]))
PY
)

# 3. Cross-install sci wheels (wasi platform) into $SCI_PKGS.
rm -rf "$SCI_PKGS"
# shellcheck disable=SC2086
pip install \
  --platform wasi_0_0_0_wasm32 \
  --python-version 3.14 \
  --target "$SCI_PKGS" \
  --only-binary=:all: \
  --no-deps \
  --index-url "file://$IDX/simple/" \
  $LIBS

# 4. Regenerate the sci-import block in app.py.
python3 /work/sci/bake/gen-sci-imports.py

# 5. Fold: sci wheels + pure deps (.venv) + app → python-env.wasm.
# NOTE: _imagingft.so now folds successfully — zlib is statically linked in the
#       pillow wheel (sci/wheels/libs/pillow.sh pre_build_hook), so inflate*
#       symbols are no longer undefined at fold time.
componentize-py -d wit -w component-world componentize \
  -p "$SCI_PKGS" \
  -p /work/.venv/lib/python3.14/site-packages \
  -p . \
  -o /work/python-env.wasm \
  app

test -s /work/python-env.wasm && echo "### SCI BAKE OK"
