#!/usr/bin/env bash
# Build componentize-py from source with the wit-component tag-skip patch.
#
# Patch: wit-component-0.245.1-skip-tag-export adds `ExternalKind::Tag => continue`
# to src/linking/metadata.rs so the shared-everything linker no longer rejects
# the __c_longjmp export tag emitted by SjLj setjmp lowering in C extensions
# that use setjmp (freetype -> matplotlib, libjpeg -> Pillow JPEG).
#
# Pin: v0.24.0 = 811ff834f1d6  (matches the known-good reference build)
# Produces: /opt/toolchain/bin/componentize-py
set -xeuo pipefail

CPY_REF="${COMPONENTIZE_PY_REF:?COMPONENTIZE_PY_REF must be set to the pinned revision (811ff834f1d6)}"
PATCHES_DIR="${PATCHES_DIR:-/opt/toolchain/patches}"

cd /opt/toolchain

# 1. Clone and pin to the exact revision
git clone https://github.com/bytecodealliance/componentize-py
cd componentize-py
git checkout "$CPY_REF"
git submodule update --init --recursive

# 2. Export WASI_SDK_PATH (required by componentize-py's build.rs for cross
#    compilation of the embedded WASI Python runtime + SQLite).
export WASI_SDK_PATH=/opt/wasi-sdk

# 2b. Install the wasm32-wasip2 Rust target: componentize-py's build.rs cross-
#     compiles internal WASI components (wit-dylib-ffi etc.) for wasm32-wasip2.
rustup target add wasm32-wasip2

# 3. Fetch all Cargo deps so wit-component-0.245.1 lands in the local registry
#    BEFORE we add the [patch.crates-io] block — cargo fetch reads the original
#    Cargo.toml and downloads the upstream crate to ~/.cargo/registry.
cargo fetch

# 4. Vendor + patch wit-component-0.245.1
#    Copy the crate out of the registry and apply our one-liner tag-skip fix.
WC=$(ls -d "$HOME"/.cargo/registry/src/*/wit-component-0.245.1)
cp -r "$WC" /opt/toolchain/wit-component-patched
patch -p1 -d /opt/toolchain/wit-component-patched \
  < "${PATCHES_DIR}/wit-component-0.245.1-skip-tag-export.patch"

# 5. Wire the patched crate into the workspace Cargo.toml
#    Path is ../wit-component-patched relative to componentize-py dir
#    (/opt/toolchain/componentize-py -> /opt/toolchain/wit-component-patched).
cat >> Cargo.toml <<'EOF'

# [ACT local patch] wit-component that skips exported SjLj __c_longjmp tags so
# setjmp-using C libs (freetype -> matplotlib, libjpeg -> Pillow JPEG) can fold.
[patch.crates-io]
wit-component = { path = "../wit-component-patched" }
EOF

# 6. Build the release binary
cargo build --release

# 7. Install to the shared toolchain bin
install -D target/release/componentize-py /opt/toolchain/bin/componentize-py
echo "### COMPONENTIZE-PY BUILD COMPLETE"
/opt/toolchain/bin/componentize-py --help
