# python-env reproducible build — design

**Date:** 2026-06-28
**Status:** Approved (design)
**Goal:** Make the `python-env` component's compilation **reproducible in CI** and the **repo self-contained**, for both the lean (pure-Python) and sci (compiled C-extension) variants — buildable identically locally and in CI via `just build [lean|sci]`.

## 1. Problem

Today the **lean** build is already CI-reproducible (`just build` → stock componentize-py via `uv`, pure-Python batteries). The **sci** build is not:

- It depends entirely on a shared, machine-local `.sci-toolchain/` (a patched componentize-py, a cross-compiled CPython, PIC+EH libc++, six cross-built C-libs, eight C-ext packages).
- The build scripts assume local paths (`$CLAUDE_JOB_DIR/tmp`, `np-venv`, `wasi-libs`).
- The C-libs are documented (`build-cdeps.md`) but not scripted; the componentize-py patch+rebuild is manual.
- The bundled-library list is **scattered** across four places with no single source of truth: the `justfile` (`-p` paths), `app.py` (the guarded imports that get frozen), the per-library build scripts (pinned versions), and `pyproject.toml` (pure deps).

None of this lives in the python-env repo, and none of it is reproducible from a clean checkout.

## 2. Approach

A **pinned toolchain image + per-library wheel builders + a fast bake**, all defined by files in the python-env repo. Chosen over (A) rebuild-everything-from-source-every-run (hours per build) and (C) commit prebuilt binaries (opaque, bloats repo).

Three stages, all reproducible because the toolchain is frozen in a `Dockerfile` and the bundled libraries are pinned in a manifest:

```
Stage 0  Toolchain image (Dockerfile)  ── the pinned, reproducible base
            wasi-sdk · cross-CPython 3.14.6 · PIC+EH libc++ ·
            patched componentize-py · C-libs (zlib/jpeg/freetype/libxml2/libxslt)
              │ (used by Stage 1 and Stage 2)
              ▼
Stage 1  Wheel builders  ── PARALLEL, one job per library
            each → a proper  cp314-…-wasi_0_0_0_wasm32  wheel
            → oras push to ghcr.io/actpkg/python-env-wheels/<lib>:<version>
              │
              ▼
Stage 2  Bake (`just build sci`)  ── fast, deterministic
            read manifest → oras pull pinned wheels → unpack → componentize fold
            → python-env.wasm (sci)
```

**Why split build from bake:** the C-ext cross-builds are slow (numpy/pandas minutes each) but change rarely (pinned versions); the fold is fast and runs on every PR. Splitting lets the wheel builders run in parallel, once per version bump, while the bake stays a quick pull+fold locally and in CI.

## 3. Why a registry (not bake-in-image, not PyPI)

- **Not PyPI:** PyPI has no WASI wheel platform tag (PEP 783 covers *Emscripten* only — `pyemscripten_*`, a different platform with a JS runtime). A `wasi_0_0_0_wasm32` wheel is rejected on upload. These wheels are also toolchain-specific (our exact wasip2 / CPython 3.14.6 ABI), not general-purpose.
- **Registry over bake-in-image:** publishing wheels to ghcr decouples "build a wheel" from "fold the component," makes the wheels reusable across components, and keeps the toolchain image free of per-version wheel churn. ghcr stores arbitrary OCI artifacts; `oras` is the push/pull tool. Fits the existing ACT OCI/ghcr distribution pattern.

## 4. The toolchain image (`Dockerfile`)

One `Dockerfile` at the repo root builds the reproducible base, layered so a single-component change rebuilds only that layer and down:

1. Base: pinned `wasi-sdk` + system build deps (cmake, ninja, meson, just, oras, uv).
2. Cross-CPython **3.14.6** (via the `dicej/wasi-wheels` recipe, pinned commit) → `libpython3.14.so` + sysconfig. Compile **libzstd** into it so `compression.zstd` is available in the stdlib for free.
3. PIC+EH libc++ (`build-libcxx-piceh.sh`).
4. Patched **componentize-py**: built from source with (a) the `wit-component` tag-skip patch (`patches/wit-component-skip-tag-export.patch`) and (b) its cpython submodule bumped to **3.14.6** to match Stage-2 ABI.
5. C-libs into a shared prefix: zlib, libjpeg-turbo, freetype, libxml2, libxslt (+ qhull staged for a future matplotlib effort) — each a script under `sci/clibs/`.

Target: **wasm32-wasip2** (see §9 for the wasip3 migration path). Built locally via `docker build`; in CI, built once and pushed to `ghcr.io/actpkg/python-env-toolchain:<tag>` so PR builds pull it.

## 5. Wheel builders (Stage 1)

One recipe per library under `sci/libs/<name>/build.sh`, each run **inside the toolchain image**. Each:

- Cross-compiles the library to wasm32-wasip2 against the cross-CPython + C-libs.
- Sets `_PYTHON_HOST_PLATFORM` so the wheel is tagged **`cp314-cp314-wasi_0_0_0_wasm32`** (a proper, self-describing wasm wheel — not the current mislabeled `linux_x86_64`).
- `oras push ghcr.io/actpkg/python-env-wheels/<name>:<version> <wheel>`.

In CI a **matrix job** runs these in parallel; it triggers only when a library's version changes in the manifest. Auth uses the workflow's `GITHUB_TOKEN` (`write:packages`).

Libraries: numpy, pandas, regex, Pillow (freetype+jpeg), msgpack, lxml, lz4, bottleneck. (Their existing `.sci-toolchain/build-scripts/build-*.sh` are the starting point — moved into the repo and de-localized.)

## 6. The manifest — single source of truth

`sci/manifest.toml` is the one place the bundled set is defined:

```toml
[lib.numpy]
version = "2.5.0"
ref     = "ghcr.io/actpkg/python-env-wheels/numpy:2.5.0"
freeze  = ["numpy", "numpy.char", "numpy.fft", "numpy.lib", "numpy.linalg",
           "numpy.ma", "numpy.polynomial", "numpy.rec", "numpy.strings"]

[lib.pillow]
version = "12.2.0"
ref     = "ghcr.io/actpkg/python-env-wheels/pillow:12.2.0"
freeze  = ["PIL.Image", "PIL.ImageFile", "PIL.ImageFont", "PIL.JpegImagePlugin", ...]
# … one [lib.*] block per bundled C-ext …
```

Derived from the manifest (no hand-syncing):
- the **bake `-p` paths** (which unpacked wheels feed the fold),
- the **`app.py` sci-import block** — generated between `# >>> sci-imports` / `# <<< sci-imports` markers from each lib's `freeze` list (componentize-py only freezes statically-imported modules),
- which **wheel builders** run and at what version.

Bumping a library = edit one `version` in the manifest → wheel-builder rebuilds + pushes → regenerate app.py block → bake.

**Publishing is tag-based (no digest pinning).** Reproducibility comes from the pinned toolchain image + pinned library versions; the `ref` tags resolve to the version-pinned wheels. (Digest pinning is a possible future hardening, not in this design.)

## 7. The bake (Stage 2) and `just build [lean|sci]`

`just build` takes a variant:

- **`just build lean`** (default) — unchanged from today: stock componentize-py via `uv`, pure-Python batteries only. No toolchain image, no network. Stays CI-buildable on a plain runner.
- **`just build sci`** — inside the toolchain image: read `manifest.toml` → `oras pull` each wheel → unpack → regenerate the `app.py` sci-import block → `componentize-py` fold → `python-env.wasm`. Fast (pull + fold), identical locally and in CI.

`just build-sci` (current name) becomes an alias of `just build sci` for back-compat.

## 8. CI workflows

- `ci.yml` (existing) — lean build + `just test` (hermetic) + `just test-net` + lint. Unchanged.
- `toolchain.yml` (new) — build the toolchain image, push to ghcr. Triggered by changes under `Dockerfile` / `sci/{clibs,toolchain,patches}/`. Manual-dispatchable.
- `wheels.yml` (new) — matrix over `sci/libs/*`, build each wheel in the toolchain image, `oras push`. Triggered by manifest version changes (or manual).
- `sci.yml` (new) — `just build sci` (pull + fold) + `just test-sci` + `just test-fs`. Runs on PRs; pulls the published toolchain image + wheels. **Not publish-gating for the lean release** (the lean tier remains the CI-blocking gate).

## 9. Toolchain provenance & risks

Pinned, and called out because the CPython-on-wasip2 path is **not officially supported** by CPython (its blessed WASI tier is Preview 1):

| Component | Pin | Note |
|---|---|---|
| wasi-sdk | 33 (exact) | provides wasm32-wasip2 sysroot; no wasip3 sysroot yet |
| wasi-wheels | commit (exact) | the cross-CPython recipe |
| CPython | **3.14.6** (stable) | both cross-build and componentize-py's bundled cpython |
| componentize-py | rev + the tag-skip patch | carries the preview1→component adapter |

**Risks:** the wasip2 CPython build is community-maintained and sensitive to upstream drift; freezing it in the image is the mitigation (insulation, not just convenience). The fold relies on the local `wit-component` tag-skip patch (enables setjmp libs: Pillow JPEG, freetype) and on `wasm_exceptions` + modern `try_table` EH — **no deprecated wasmtime flags**.

**wasip3 migration (future, not in scope):** when wasi-sdk ships a stable `wasm32-wasip3` sysroot *and* componentize-py can emit wasip3 components, migration is: bump those two pins + flip `--target` in the image. The image-pins-everything design makes that a small, contained change.

## 10. Non-goals / out of scope

- **matplotlib** — parked (separate wasm port; `import` memory-corruption is unresolved). Its artifacts stay in a `matplotlib-wip` area, not in the sci bundle.
- **Digest-pinned / cosign-signed wheels** — noted as future hardening; this design is tag-based.
- **Changing the lean tier** — untouched; it remains the CI-gating, plain-runner build.
- **A WASI PEP-783 equivalent** — doesn't exist; we self-host on ghcr until one does.

## 11. Implementation phasing

This is large; the implementation plan should decompose into independently-verifiable phases, built bottom-up:

1. **Toolchain image** — the `Dockerfile` (wasi-sdk, cross-CPython 3.14.6 + zstd, libc++, patched componentize-py, C-libs). Verify: image builds; a trivial component folds + runs.
2. **Wheel builders + manifest** — `sci/manifest.toml`, `sci/libs/*/build.sh` producing proper-tagged wheels, `oras push`. Verify: each wheel builds in the image and pushes/pulls from ghcr.
3. **Manifest-driven bake** — `app.py` sci-import codegen, manifest-driven `-p`, `just build [lean|sci]`. Verify: `just build sci` pulls + folds; `test-sci` + `test-fs` pass; lean unchanged.
4. **CI workflows** — `toolchain.yml`, `wheels.yml`, `sci.yml`. Verify: a clean CI run reproduces the component end-to-end.

Each phase leaves the repo in a working state (lean build never regresses).

## 12. Validation

The build is "reproducible" when, from a clean checkout on a clean machine:
1. `docker build` produces the toolchain image (or `docker pull` the pinned one).
2. `just build lean` and `just build sci` both produce a working component.
3. `just test`, `just test-sci`, `just test-fs` pass.
4. A second run produces a byte-equivalent `python-env.wasm` (modulo any non-determinism in componentize-py/Wizer, which is to be verified and, if present, documented).
