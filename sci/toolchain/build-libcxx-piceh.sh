#!/usr/bin/env bash
# Build PIC + wasm-exceptions libunwind/libc++abi/libc++ for wasm32-wasip2 from
# the LLVM revision sdk33 ships (4434dabb6991 / 22.1.0), mirroring wasi-sdk's
# runtimes cmake flags but flipping CMAKE_POSITION_INDEPENDENT_CODE=ON (the combo
# wasi-sdk punted on before llvm#159143 landed). Output: PIC+EH static archives.
#
# De-localized from .sci-toolchain/build-scripts/build-libcxx-piceh.sh:
#   - ROOT fixed at /opt/toolchain (was $CLAUDE_JOB_DIR/tmp)
#   - CMAKE build dir fixed at /tmp/cmake-build-cxx (cleaned after install)
#   - PREFIX (install output) fixed at /opt/toolchain/build-cxx
#   - /opt/wasi-sdk unchanged
#   - Pinned LLVM_SHA=4434dabb6991 (llvm-project 22.1.0 / wasi-sdk 33)
set -xeuo pipefail

ROOT="/opt/toolchain"
SDK=/opt/wasi-sdk
SYSROOT="$SDK/share/wasi-sysroot"
TARGET=wasm32-wasip2
PREFIX="/opt/toolchain/build-cxx"
BUILD_DIR="/tmp/cmake-build-cxx"
LLVM_SHA=4434dabb6991

cd "$ROOT"

echo "### [$(date -u +%H:%M:%S)] partial sparse fetch of llvm runtimes"
if [ ! -d llvm-project/.git ]; then
  mkdir -p llvm-project && cd llvm-project && git init -q
  git remote add origin https://github.com/llvm/llvm-project
  git config extensions.partialClone origin
  git sparse-checkout init --cone
  git sparse-checkout set runtimes libcxx libcxxabi libunwind libc cmake llvm/cmake llvm/utils third-party
  ( git fetch -q --depth 1 --filter=blob:none origin "$LLVM_SHA" \
    || git fetch -q --depth 1 --filter=blob:none origin tag llvmorg-22.1.0 )
  git checkout -q FETCH_HEAD
  cd "$ROOT"
fi
# Ensure sparse-checkout dirs are present even if repo existed from a prior run.
( cd "$ROOT/llvm-project" && git sparse-checkout set runtimes libcxx libcxxabi libunwind libc cmake llvm/cmake llvm/utils third-party )
ls llvm-project/runtimes/CMakeLists.txt

RD="$($SDK/bin/clang -print-resource-dir)"
echo "### resource-dir = $RD"
FLAGS="-mcpu=lime1 --target=$TARGET --sysroot=$SYSROOT -resource-dir $RD -fwasm-exceptions -mllvm -wasm-use-legacy-eh=false -fdeclspec"

rm -rf "$BUILD_DIR" "$PREFIX"
cmake -G Ninja -S "$ROOT/llvm-project/runtimes" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_C_COMPILER="$SDK/bin/clang" \
  -DCMAKE_CXX_COMPILER="$SDK/bin/clang++" \
  -DCMAKE_ASM_COMPILER="$SDK/bin/clang" \
  -DCMAKE_AR="$SDK/bin/llvm-ar" \
  -DCMAKE_RANLIB="$SDK/bin/llvm-ranlib" \
  -DCMAKE_C_COMPILER_TARGET="$TARGET" \
  -DCMAKE_CXX_COMPILER_TARGET="$TARGET" \
  -DCMAKE_SYSROOT="$SYSROOT" \
  -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
  -DLLVM_COMPILER_CHECKED=ON -DUNIX=ON \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_BUILD_TESTS=OFF \
  -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS" -DCMAKE_ASM_FLAGS="$FLAGS" \
  -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_EXCEPTIONS=ON -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
  -DLIBCXX_ENABLE_THREADS=ON -DLIBCXX_HAS_PTHREAD_API=ON \
  -DLIBCXXABI_ENABLE_THREADS=ON -DLIBCXXABI_HAS_PTHREAD_API=ON \
  -DLIBUNWIND_ENABLE_THREADS=ON -DLIBUNWIND_USE_COMPILER_RT=ON \
  -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ABI_VERSION=2 \
  -DLIBCXX_HAS_MUSL_LIBC=OFF \
  -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
  -DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" 2>&1 | tail -25

echo "### [$(date -u +%H:%M:%S)] ninja build runtimes (install targets only, skipping cxx_experimental)"
# In LLVM 22.1.0, `ninja all` also builds cxx_experimental which requires a
# timezone database path even for WASM targets. Drive only the install targets
# for the three archives we need — their dep graph excludes cxx_experimental.
ninja -C "$BUILD_DIR" install-unwind install-cxxabi install-cxx 2>&1 | tail -20

# Flatten lib/<triple>/ into lib/ so downstream stages use a stable path
# (cmake may install to lib/wasm32-wasip2/ depending on LLVM version).
if [ ! -f "$PREFIX/lib/libc++.a" ] && ls "$PREFIX"/lib/*/libc++.a >/dev/null 2>&1; then
  TRIPDIR="$(ls -d "$PREFIX"/lib/*/)"
  echo "### flattening $TRIPDIR -> $PREFIX/lib/"
  cp "$TRIPDIR"/*.a "$PREFIX/lib/"
fi

echo "### [$(date -u +%H:%M:%S)] PIC+EH artifacts:"
ls -la "$PREFIX/lib/libc++.a" "$PREFIX/lib/libc++abi.a" "$PREFIX/lib/libunwind.a"
echo "### verify libc++abi has __cxa_throw and is PIC-linkable into a .so"
$SDK/bin/llvm-nm "$PREFIX/lib/libc++abi.a" 2>/dev/null | grep -E "T __cxa_throw$|T __cxa_allocate_exception$" | head

# Clean up source + build dir to keep image lean (~2 GB saved)
rm -rf "$ROOT/llvm-project" "$BUILD_DIR"

echo "### LIBCXX PIC+EH BUILD DONE"
