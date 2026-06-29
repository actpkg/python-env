# Task 7 Report: Pin Rust for Reproducible componentize Build

## Diagnosis

### Failing→Passing

**Root cause**: `base` stage installs `--default-toolchain stable` (unpinned).
`componentize-py v0.24.0` builds `pyo3-macros` as a host proc-macro crate.
When rust-lld is the default host linker (Rust ≥ 1.86.0), certain LLVM versions
produce `.eh_frame` sections with CIE offsets that lld rejects:

```
rust-lld: error: ...libpyo3_macros_backend-*.rlib(...rcgu.o):(.eh_frame): invalid CIE reference
error: could not compile `pyo3-macros`
thread 'main' panicked at build.rs:560:5: assertion failed: status.success()
```

Because `stable` advances without the Dockerfile changing, the image is not
reproducible — a clean `docker build` on a future date may land a new stable
that re-introduces the bug.

### Investigation

Tested inside `python-env-toolchain:libcxx` (the parent stage):

1. **Rust 1.87.0** — installs cleanly, `pyo3-macros` alone links, BUT the
   full componentize-py dependency tree (`wasmtime 43.0.2`, `cranelift 0.130.2`,
   `gimli 0.33.0`) has MSRV **1.91.0** — cargo fetch aborts with:
   `wasmtime@43.0.2 requires rustc 1.91.0` (and ~50 similar errors).
   Task description's suggested range (1.84.x–1.86.x) is below that MSRV.

2. **Rust 1.96.0** (LLVM 22.1.2, current stable at time of fix) — full
   componentize-py build succeeds without errors. This is also the version
   present in the pre-built `python-env-toolchain:componentize` image.

### Why LLVM 22 / Rust 1.96.0 works

LLVM 22's lld fixed the `.eh_frame` CIE reference handling that broke with
the LLVM 20–21 era lld when linking rcgu objects from Rust proc-macro crates.
Rust 1.96.0 ships LLVM 22.1.2, so the linker bug is no longer present.

## Fix Applied

**File**: `sci/toolchain/build-componentize-py.sh`

### 1. Pin Rust to 1.96.0

```bash
RUST_PIN="1.96.0"
rustup toolchain install "${RUST_PIN}" --profile minimal
rustup default "${RUST_PIN}"
```

Rationale:
- Satisfies wasmtime 43.0.2 / cranelift 0.130.2 MSRV of ≥ 1.91.0
- LLVM 22.1.2 ships a fixed lld — no `.eh_frame` CIE error
- Deterministic: independent of what `stable` resolves to at build time

### 2. Force GNU ld for host target (defense-in-depth)

```toml
[target.x86_64-unknown-linux-gnu]
linker = "cc"
rustflags = ["-C", "link-arg=-fuse-ld=bfd"]
```

Written to `~/.cargo/config.toml` inside the build script.

Rationale:
- `linker = "cc"` tells Cargo to use the system C compiler frontend (GCC on
  Ubuntu 24.04) as the linker, bypassing any rust-lld invocation path.
- `-fuse-ld=bfd` explicitly selects ld.bfd (GNU binutils, always present via
  `build-essential` in the base stage).
- Protects against future Rust/LLVM releases re-introducing the lld bug.
- Note: `linker-features=-lld` (the flag suggested in the task) is NOT
  available in Rust 1.87.0; it was added later. The `linker = "cc"` approach
  works since Cargo 1.0 and is version-independent.

## Also Fixed

**File**: `sci/smoke/run-smoke.sh`

Changed:
```bash
wasm-tools validate "${OUTPUT}"
```
To:
```bash
wasm-tools validate --features component-model "${OUTPUT}"
```

`smoke.wasm` is a WebAssembly component binary; wasm-tools requires
`--features component-model` to validate component-model structure instead of
treating it as a core module.

## Clean Build Verify Output

```
docker build --network=host --target componentize -t python-env-toolchain:componentize <path>
```

Results:
- `base`, `cpython`, `libcxx` stages: **CACHED** (no invalidation)
- `componentize` stage: rebuilt in **410 seconds** (~7 min)
- Final output: `### COMPONENTIZE-PY BUILD COMPLETE`

```
docker run --rm python-env-toolchain:componentize componentize-py --version
componentize-py 0.24.0
```

Build succeeded. No pyo3-macros link error. `--version` confirms correct binary.
