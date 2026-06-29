#!/usr/bin/env bash
# msgpack lib descriptor for build-wheel.sh
# C++ extension (Cython → C++, uses C++ exceptions, no external deps).
# Requires -fwasm-exceptions so the wasm EH proposal is used instead of SJLJ.
# Linking: build-wheel.sh sets CXX=clang++ wrapper; Python's UnixCCompiler uses
# CXX (not LDSHARED) for language='c++' extensions, so libc++ is linked
# automatically.  $LIBCXX is already on the search path via -L$LIBCXX in LDFLAGS.
# Sourced by build-wheel.sh (venv already active; $SRC available).

LIB_VERSION="1.2.1"
BUILD_DEPS=("Cython>=3")
EXTRA_CFLAGS="-fwasm-exceptions -mllvm -wasm-use-legacy-eh=false"

fetch_source() {
  python -m pip download --no-binary msgpack --no-deps "msgpack==${LIB_VERSION}" -d "$SRC"
  tar xf "$SRC"/msgpack-*.tar.gz -C "$SRC" --strip-components=1
}
