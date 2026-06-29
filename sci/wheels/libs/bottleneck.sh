#!/usr/bin/env bash
# bottleneck lib descriptor for build-wheel.sh
# Plain C (no C++ exceptions); setuptools build. Needs WASM numpy headers at
# compile time: WASM int64 = long long (64-bit), host int64 = long (also 64-bit
# on x86_64 but format chars differ: 'q' vs 'l' in Cython/struct). Using host
# numpy headers in a WASM build causes dtype mismatch at runtime.
# De-localized from build-bottleneck.sh; paths updated to image layout.
# Sourced by build-wheel.sh (venv active; $SRC, $CROSS available).

LIB_VERSION="1.6.0"
BUILD_DEPS=("setuptools" "numpy==2.5.0" "versioneer[toml]")

# WASM numpy headers prepended in pre_build_hook; no C++ exceptions needed.
# Fixed extraction path so EXTRA_CFLAGS can reference it at source time.
_BOTTLENECK_NUMPY_INC=/tmp/bn-numpy-wasm-include
EXTRA_CFLAGS="-I$_BOTTLENECK_NUMPY_INC"

fetch_source() {
  # pip download with _PYTHON_HOST_PLATFORM=wasi triggers a numpy build-dep chain
  # (bottleneck's build system requires numpy); unset so pip downloads native wheels.
  python - "${LIB_VERSION}" "$SRC" <<'PY'
import json, shutil, sys, urllib.request
ver, out_dir = sys.argv[1], sys.argv[2]
data = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/Bottleneck/{ver}/json"))
url = next(u["url"] for u in data["urls"] if u["packagetype"] == "sdist")
out = f"{out_dir}/Bottleneck-{ver}.tar.gz"
print(f"Downloading {url}", flush=True)
with urllib.request.urlopen(url) as r, open(out, "wb") as f:
    shutil.copyfileobj(r, f)
PY
  tar xf "$SRC"/Bottleneck-*.tar.gz -C "$SRC" --strip-components=1
}

# Called by build-wheel.sh after cross env is set, cwd = $SRC.
pre_build_hook() {
  # ── Extract WASM numpy headers ────────────────────────────────────────────
  # Host numpy (in venv) reports x86_64 int64='l'; WASM numpy reports 'q'.
  # Prepend WASM numpy headers so they win over host numpy include (which
  # setuptools would add via numpy.get_include() as a later -I flag).
  local NUMPY_WHL
  NUMPY_WHL=$(ls /work/dist/numpy-*-wasi_0_0_0_wasm32.whl 2>/dev/null | head -1)
  if [ -z "$NUMPY_WHL" ]; then
    echo "ERROR: no WASM numpy wheel found in /work/dist" >&2
    exit 1
  fi
  rm -rf "$_BOTTLENECK_NUMPY_INC"
  mkdir -p "$_BOTTLENECK_NUMPY_INC"
  python3 - "$NUMPY_WHL" "$_BOTTLENECK_NUMPY_INC" <<'PY'
import sys, zipfile, os
whl, dst = sys.argv[1], sys.argv[2]
# Wheel path: numpy/_core/include/numpy/*.h → extract to dst/numpy/*.h
# so that -I$dst makes '#include "numpy/npy_common.h"' resolve correctly.
with zipfile.ZipFile(whl) as z:
    prefix = "numpy/_core/include/"
    for name in z.namelist():
        if name.startswith(prefix):
            rel = name[len(prefix):]  # e.g. "numpy/npy_common.h"
            out = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with z.open(name) as src, open(out, "wb") as f:
                f.write(src.read())
print(f"Extracted WASM numpy headers to {dst}")
PY
}
