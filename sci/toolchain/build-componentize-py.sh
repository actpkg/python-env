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

# ── Reproducible Rust toolchain ────────────────────────────────────────────────
# The base stage installs an unpinned `stable` toolchain whose lld linker may
# hit an `.eh_frame` CIE bug when linking host proc-macro crates (pyo3-macros).
# Fix: switch to an exact toolchain version BEFORE building, so this stage is
# deterministic regardless of what `stable` resolves to at build time.
#
# Pin: 1.96.0 (LLVM 22.1.2, 2026-05-25)
#   - Satisfies the effective MSRV of componentize-py v0.24.0's dependencies:
#       wasmtime 43.0.2 + cranelift 0.130.2 require rustc >= 1.91.0
#   - Verified to compile componentize-py v0.24.0 without linker errors
#   - LLVM 22 ships a fixed lld that no longer mis-handles .eh_frame CIE refs
# ───────────────────────────────────────────────────────────────────────────────
RUST_PIN="1.96.0"
rustup toolchain install "${RUST_PIN}" --profile minimal
rustup default "${RUST_PIN}"

# Also force GNU ld (bfd) for the host x86_64 target to avoid any rust-lld
# `.eh_frame` regressions across future Rust/LLVM releases.  The base image's
# build-essential provides /usr/bin/ld.bfd (GNU binutils).
# We use `linker = "cc"` (stable since Cargo 1.0) to tell Cargo to use the
# system C compiler frontend (GCC on Ubuntu) as the linker.  Passing
# -fuse-ld=bfd via rustflags selects ld.bfd explicitly, bypassing rust-lld.
mkdir -p ~/.cargo
cat > ~/.cargo/config.toml <<'CARGO_TOML'
[target.x86_64-unknown-linux-gnu]
linker = "cc"
rustflags = ["-C", "link-arg=-fuse-ld=bfd"]
CARGO_TOML

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

# 3b. Patch src/lib.rs: enable the wasm exceptions proposal in the wasmtime
#     Config so that Pillow and other C extensions built with wasm-EH SjLj
#     lowering (which emits exception tags) can be folded by componentize-py.
#     The insert point is the line that enables component-model-async — we add
#     wasm_exceptions(true) immediately after it.
python3 - <<'PY'
import sys
p = "src/lib.rs"
s = open(p).read()
needle = "config.wasm_component_model_async(true);"
replacement = needle + "\n    config.wasm_exceptions(true); // ACT: enable wasm-EH for sci C-extension wheels"
if "wasm_exceptions" not in s:
    if needle not in s:
        print(f"ERROR: needle not found in {p}; cannot apply exceptions patch", file=sys.stderr)
        sys.exit(1)
    open(p, "w").write(s.replace(needle, replacement, 1))
    print(f"patched {p}: added wasm_exceptions(true)")
else:
    print(f"{p}: wasm_exceptions already present, skipping patch")
PY

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
