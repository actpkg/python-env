#!/usr/bin/env bash
# Build a wasm32-wasip2 CPython 3.14.6 cross-dev environment for the toolchain
# image: libpython3.14.so + headers + sysconfigdata. De-localized from
# dicej/wasi-wheels' known-good recipe.
#
# TWO wasi-SDKs BY DESIGN -- do NOT reconcile them:
#   * wasi-wheels' Makefile downloads its OWN wasi-sdk 27.0 (build/wasi-sdk) and
#     builds CPython with it; this stage uses that 27.
#   * The base image's /opt/wasi-sdk (33, clang 22) is for the later C-libs /
#     C-ext stages (modern-EH flag). The two outputs are wasm-ABI compatible.
#
# CPYTHON VERSION BUMP -- why we don't just `git checkout v3.14.6`:
#   wasi-wheels pins its cpython submodule (dicej/cpython @ 267f0e22) to
#   3.14.0rc3 + 4 WASI patches. The plan wants stable 3.14.6. The dicej fork has
#   NO v3.14.6 tag, and its 4th patch (comment-out _fallback_socketpair auth) is
#   already obsoleted upstream -- 3.14.6 ships the same fix as gh-146139
#   (`if sys.platform != "wasi":`). So we build UPSTREAM python/cpython v3.14.6
#   and re-apply only the 3 still-relevant WASI patches as one vendored diff:
#       sci/patches/cpython-3.14.6-wasi.patch
#   (configure WASI-dynamic-linking enable, --target=wasm32-wasip2 hard-code,
#    WASI stack-overflow-check disable; verified to apply cleanly on v3.14.6).
#
# NOTE: zstd / compression.zstd is DEFERRED. CPython 3.14's _zstd module needs a
#   libzstd, and wasi-wheels builds a HOST CPython first then the wasip2 cross
#   one -- a single libzstd can't satisfy both (host=native, cross=wasm), and a
#   global LIBZSTD_* env poisons the host link. Wiring a host+cross libzstd split
#   is out of scope for this stage; tracked as a follow-up. The pure-Python
#   `compression/zstd/` package is still present in the staged stdlib (it just
#   imports the absent _zstd lazily).
set -xeuo pipefail

WASI_WHEELS_REF="${WASI_WHEELS_REF:?pin the wasi-wheels commit}"
CPYTHON_TAG="v3.14.6"
CPYTHON_WASI_PATCH="${CPYTHON_WASI_PATCH:-/opt/toolchain/sci/patches/cpython-3.14.6-wasi.patch}"

cd /opt/toolchain
git clone https://github.com/dicej/wasi-wheels
cd wasi-wheels
git checkout "$WASI_WHEELS_REF"
ABS="$(pwd)"

# --- CPython source = upstream v3.14.6 + the 3 still-relevant dicej WASI patches
git submodule update --init --depth 1 cpython            # establishes cpython/ (dicej rc3)
git -C cpython remote add upstream https://github.com/python/cpython
git -C cpython fetch --depth 1 upstream tag "$CPYTHON_TAG"
git -C cpython checkout --quiet "$CPYTHON_TAG"
git -C cpython apply --verbose "$CPYTHON_WASI_PATCH"
grep -q '"3.14.6"' cpython/Include/patchlevel.h          # fail fast if not 3.14.6

# --- wasi-wheels' own wasi-sdk 27 (downloaded via its Makefile target)
make "$ABS/build/wasi-sdk"

# --- Build CPython (host python + wasip2 cross + linked libpython3.14.so)
make "$ABS/cpython/builddir/wasi/install"

# --- Stage outputs at stable paths for later stages
mkdir -p /opt/toolchain/cpython/install
cp -a "$ABS/cpython/builddir/wasi/install/." /opt/toolchain/cpython/install/
cp -a "$ABS/cpython/builddir/wasi/build/lib.wasi-wasm32-3.14" /opt/toolchain/cpython/sysconfig
test -f /opt/toolchain/cpython/install/lib/libpython3.14.so

# --- Verify: SOABI + version
grep -m1 "'SOABI'" /opt/toolchain/cpython/sysconfig/_sysconfigdata__wasi_wasm32-wasi.py
grep -m1 PY_VERSION "$ABS/cpython/Include/patchlevel.h"
echo "### CPYTHON 3.14.6 BUILD COMPLETE"
