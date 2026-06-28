#!/usr/bin/env bash
# Build a wasm32-wasip2 CPython 3.14.6 cross-dev environment for the toolchain
# image: libpython3.14.so + headers + sysconfigdata, staged at
# /opt/toolchain/cpython/{install,sysconfig}.
#
# SELF-CONTAINED (user directive 2026-06-29): builds UPSTREAM python/cpython
# v3.14.6 from source -- NO build-time dependency on dicej/benbrandt wasi-wheels
# (their Makefiles + CPython's own Tools/wasm/wasi/__main__.py are the reference
# the host+cross recipe below is derived from, nothing more).
#
# SINGLE wasi-sdk: the cross build uses the image's /opt/wasi-sdk (33, clang 22)
# -- the same SDK libc++ and the C-extensions use -- so the whole image is
# ABI-consistent on one toolchain. (The old two-SDK split with wasi-wheels'
# wasi-sdk 27 is gone.)
#
# WASI deltas come from the vendored patch sci/patches/cpython-3.14.6-wasi.patch
# (dicej's still-relevant WASI patches rebased onto upstream v3.14.6: enable WASI
# shared/dynamic linking in configure, hard-code --target=wasm32-wasip2 in
# Tools/wasm/wasi-env, the __wasi__ stack-check + socket/expat fixes). The 4th
# dicej patch is obsolete -- 3.14.6 already ships the same fix as gh-146139.
#
# zstd / compression.zstd is DEFERRED (out of scope): CPython 3.14's _zstd needs
# a libzstd; the pure-Python compression/zstd package is still staged, only the
# _zstd C extension is absent.
set -xeuo pipefail

CPYTHON_TAG="v3.14.6"
SDK=/opt/wasi-sdk
SRC=/opt/toolchain/cpython-src
PATCH="${CPYTHON_WASI_PATCH:-/opt/toolchain/sci/patches/cpython-3.14.6-wasi.patch}"
INSTALL=/opt/toolchain/cpython/install
HOST_TRIPLE=wasm32-unknown-wasip2           # -> MULTIARCH wasm32-wasi, SOABI cpython-314-wasm32-wasi
WASM_CFLAGS="-fPIC -mcpu=lime1"

# --- Upstream CPython v3.14.6 + vendored WASI patch
git clone --depth 1 --branch "$CPYTHON_TAG" https://github.com/python/cpython "$SRC"
cd "$SRC"
patch -p1 < "$PATCH"
grep -q '"3.14.6"' Include/patchlevel.h     # fail fast if not 3.14.6
BUILD_TRIPLE="$(./config.guess)"

# --- 1) HOST python (system gcc, out-of-tree so the source stays VPATH-clean).
#        Not installed -- used in-place as --with-build-python for the cross build
#        (matches Tools/wasm/wasi/__main__.py and the wasi-wheels Makefiles).
mkdir -p "$SRC/builddir/build"
cd "$SRC/builddir/build"
../../configure -C
make -j"$(nproc)"
BUILD_PYTHON="$SRC/builddir/build/python"
test -x "$BUILD_PYTHON"

# --- 2) CROSS wasm32-wasip2 python against /opt/wasi-sdk (out-of-tree). The
#        configure path MUST be relative (so the interpreter locates the stdlib
#        from within the checkout); run via the patched wasi-env wrapper.
mkdir -p "$SRC/builddir/wasi"
cd "$SRC/builddir/wasi"
WASI_SDK_PATH="$SDK" \
CONFIG_SITE=../../Tools/wasm/wasi/config.site-wasm32-wasi \
CFLAGS="$WASM_CFLAGS" \
../../Tools/wasm/wasi-env ../../configure -C \
  --host="$HOST_TRIPLE" \
  --build="$BUILD_TRIPLE" \
  --with-build-python="$BUILD_PYTHON" \
  --prefix="$INSTALL" \
  --enable-wasm-dynamic-linking \
  --enable-ipv6 \
  --disable-test-modules
make build_all -j"$(nproc)"
make install

# --- Assemble the shared libpython3.14.so from the static core + vendored deps
#     (HACL / libmpdec / libexpat, built under builddir/wasi/Modules) + the
#     wasi emulated libs. Mirrors the wasi-wheels link step.
EXTRA_A="$(find "$SRC/builddir/wasi/Modules" -name '*.a' | sort)"
"$SDK/bin/clang" --target=wasm32-wasip2 -mcpu=lime1 -shared \
  -o "$INSTALL/lib/libpython3.14.so" \
  -Wl,--whole-archive "$INSTALL/lib/libpython3.14.a" -Wl,--no-whole-archive \
  $EXTRA_A \
  -lwasi-emulated-signal \
  -lwasi-emulated-getpid \
  -lwasi-emulated-process-clocks \
  -ldl

# --- Stage sysconfig at a stable path for later stages
cp -a "$SRC/builddir/wasi/build/lib.wasi-wasm32-3.14" /opt/toolchain/cpython/sysconfig
test -f "$INSTALL/lib/libpython3.14.so"

# --- Verify: SOABI + version
grep -m1 "'SOABI'" /opt/toolchain/cpython/sysconfig/_sysconfigdata__wasi_wasm32-wasi.py
grep -m1 PY_VERSION "$INSTALL/include/python3.14/patchlevel.h"
echo "### CPYTHON 3.14.6 BUILD COMPLETE"
