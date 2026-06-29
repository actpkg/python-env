#!/usr/bin/env bash
# lz4 lib descriptor for build-wheel.sh
# lz4-python bundles liblz4 C sources (PYLZ4_USE_SYSTEM_LZ4=False), so no
# external liblz4.a is needed — plain C, no setjmp → folds cleanly.
# Sourced by build-wheel.sh (venv already active; $SRC, $CROSS available).

LIB_VERSION="4.4.5"
BUILD_DEPS=("pkgconfig" "setuptools_scm[toml]>=6.2")
export PYLZ4_USE_SYSTEM_LZ4=False   # use bundled liblz4 sources (no system dep)

fetch_source() {
  python -m pip download --no-binary lz4 --no-deps "lz4==${LIB_VERSION}" -d "$SRC"
  tar xf "$SRC"/lz4-*.tar.gz -C "$SRC" --strip-components=1
}
