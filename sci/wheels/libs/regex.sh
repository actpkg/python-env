#!/usr/bin/env bash
# regex lib descriptor for build-wheel.sh
# Pure C extension; sdist ships Cython-generated .c files so no Cython dep needed.
# No external libs required — straightforward cross-build.
# Sourced by build-wheel.sh (venv already active; $SRC available).

LIB_VERSION="2026.5.9"
BUILD_DEPS=()

fetch_source() {
  python -m pip download --no-binary regex --no-deps "regex==${LIB_VERSION}" -d "$SRC"
  tar xf "$SRC"/regex-*.tar.gz -C "$SRC" --strip-components=1
}
