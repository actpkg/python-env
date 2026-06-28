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

A **pinned toolchain image + per-library wheel builders + a fast bake**, all defined by files in the python-env repo, with `pyproject.toml` as the single source of truth. Chosen over (A) rebuild-everything-from-source-every-run (hours per build) and (C) commit prebuilt binaries (opaque, bloats repo).

Three stages, reproducible because the toolchain is frozen in a `Dockerfile` and the bundled libraries are pinned in `pyproject.toml`:

```
Stage 0  Toolchain image (Dockerfile)  ── the pinned, reproducible base
            wasi-sdk · cross-CPython 3.14.6 · PIC+EH libc++ ·
            patched componentize-py · C-libs (zlib/jpeg/freetype/libxml2/libxslt)
              │ (used by Stage 1 and Stage 2)
              ▼
Stage 1  Wheel builders  ── PARALLEL, one job per library
            each → a proper  cp314-cp314-wasi_0_0_0_wasm32  wheel
            → uploaded as a GitHub Release asset; PEP 503 index (GH Pages) updated
              │
              ▼
Stage 2  Bake (`just build sci`)  ── fast, deterministic
            pip cross-install the sci dep-group from our index → componentize fold
            → python-env.wasm (sci)
```

**Why split build from bake:** the C-ext cross-builds are slow (numpy/pandas minutes each) but change rarely (pinned versions); the fold is fast and runs on every PR. Splitting lets the wheel builders run in parallel, once per version bump, while the bake stays a quick install+fold locally and in CI.

## 3. Distribution: a PEP 503 index (not PyPI, not ghcr/oras)

- **Not PyPI:** PyPI has no WASI wheel platform tag (PEP 783 covers *Emscripten* only — `pyemscripten_*`, a different platform with a JS runtime). A `wasi_0_0_0_wasm32` wheel is rejected on upload. These wheels are also toolchain-specific (our exact wasip2 / CPython 3.14.6 ABI), not general-purpose.
- **A PEP 503 "simple" index, so `pip`/`uv` can resolve the wheels** — because the bundled set is declared in `pyproject.toml` (§6) and installed with standard tooling (§7), the wheels must live somewhere pip can read. We self-host a **static simple-index on GitHub Pages** pointing at wheels stored as **GitHub Release assets**. Both are free, static, and need no server.
- **Why not ghcr/oras:** OCI registries aren't pip-installable, so they can't back a `pyproject.toml`-driven install. (Trade-off accepted: we forgo OCI/cosign signing of the *wheels*; they're build inputs, not the distributed component. Signing the component itself is unaffected.)

## 4. The toolchain image (`Dockerfile`)

One `Dockerfile` at the repo root builds the reproducible base, layered so a single-component change rebuilds only that layer and down:

1. Base: pinned `wasi-sdk` + system build deps (cmake, ninja, meson, just, uv).
2. Cross-CPython **3.14.6** (via the `dicej/wasi-wheels` recipe, pinned commit) → `libpython3.14.so` + sysconfig. Compile **libzstd** into it so `compression.zstd` is available in the stdlib for free.
3. PIC+EH libc++ (`build-libcxx-piceh.sh`).
4. Patched **componentize-py**: built from source with (a) the `wit-component` tag-skip patch (`patches/wit-component-skip-tag-export.patch`) and (b) its cpython submodule bumped to **3.14.6** to match Stage-2 ABI.
5. C-libs into a shared prefix: zlib, libjpeg-turbo, freetype, libxml2, libxslt (+ qhull staged for a future matplotlib effort) — each a script under `sci/clibs/`.

Target: **wasm32-wasip2** (see §9 for the wasip3 migration path). Built locally via `docker build`; in CI, built once and pushed to `ghcr.io/actpkg/python-env-toolchain:<tag>` (a *container image* — OCI is fine here) so PR builds pull it.

## 5. Wheel builders (Stage 1)

One recipe per library under `sci/libs/<name>/build.sh`, each run **inside the toolchain image**. Each:

- Cross-compiles the library to wasm32-wasip2 against the cross-CPython + C-libs.
- Sets `_PYTHON_HOST_PLATFORM` so the wheel is tagged **`cp314-cp314-wasi_0_0_0_wasm32`** (a proper, self-describing wasm wheel — not the current mislabeled `linux_x86_64`).
- Publishes: upload the wheel as a **GitHub Release asset** and regenerate the **PEP 503 simple-index** on GitHub Pages (add the wheel's `<a href>` under `/simple/<name>/`).

In CI a **matrix job** runs these in parallel; it triggers only when a library's version changes in `pyproject.toml`. Auth uses the workflow's `GITHUB_TOKEN` (release upload + Pages deploy).

Libraries: numpy, pandas, regex, Pillow (freetype+jpeg), msgpack, lxml, lz4, bottleneck. (Their existing `.sci-toolchain/build-scripts/build-*.sh` are the starting point — moved into the repo and de-localized.)

## 6. `pyproject.toml` — single source of truth

`pyproject.toml` defines **both** tiers and the freeze map, replacing the old scattered state:

```toml
[project]
dependencies = [ "jinja2", "beautifulsoup4", ... ]   # lean tier (pure, host-installable)

[dependency-groups]
sci = [                                              # sci tier (wasm C-ext wheels)
  "numpy==2.5.0", "pandas==3.0.3", "regex==2026.5.9", "Pillow==12.2.0",
  "msgpack==1.2.1", "lxml==6.1.1", "lz4==4.4.5", "bottleneck==1.6.0",
]

[tool.python-env.freeze]                             # what app.py must pre-import
numpy  = ["numpy", "numpy.char", "numpy.fft", "numpy.lib", "numpy.linalg",
          "numpy.ma", "numpy.polynomial", "numpy.rec", "numpy.strings"]
pillow = ["PIL.Image", "PIL.ImageFile", "PIL.ImageFont", "PIL.JpegImagePlugin", ...]
# … one entry per bundled C-ext …

[[tool.uv.index]]                                    # our PEP 503 index
name = "python-env-wasi"
url  = "https://actpkg.github.io/python-env-wheels/simple/"
```

Derived (no hand-syncing):
- the **sci dep set + pinned versions** → the wheel builders and the bake's cross-install (§7),
- the **`app.py` sci-import block** → generated between `# >>> sci-imports` / `# <<< sci-imports` markers from `[tool.python-env.freeze]` (componentize-py only freezes statically-imported modules).

Bumping a library = edit one version in `[dependency-groups].sci` → wheel-builder rebuilds + republishes → regenerate the app.py block → bake. Pinning is by **exact version** (`==`); reproducibility comes from the pinned toolchain image + exact versions resolved from our index. (Hash pinning is possible future hardening, not in this design.)

## 7. The bake (Stage 2) and `just build [lean|sci]`

`just build` takes a variant:

- **`just build lean`** (default) — unchanged: `uv sync` the pure batteries → stock componentize-py fold. No toolchain image, no wasm index. Stays CI-buildable on a plain runner.
- **`just build sci`** — inside the toolchain image:
  1. **Cross-install** the `sci` group into a target dir (the host can't *run* wasm wheels, so this is a download+unpack, not a `uv sync`):
     ```bash
     pip install --platform wasi_0_0_0_wasm32 --python-version 3.14 \
         --target sci-pkgs --only-binary=:all: --no-deps \
         --index-url https://actpkg.github.io/python-env-wheels/simple/ \
         numpy==2.5.0 pandas==3.0.3 …      # list read from pyproject's sci group
     ```
     (`pip`'s `--platform` takes a freeform tag, so `wasi_*_wasm32` resolves; `uv`'s `--python-platform` is an enum that may not know wasi yet, so the cross-install step uses `pip` even though the *list* comes from `pyproject.toml`.)
  2. Regenerate the `app.py` sci-import block from `[tool.python-env.freeze]`.
  3. `componentize-py … -p sci-pkgs -p .venv/.../site-packages -p . …` → `python-env.wasm`.

  Fast (download + fold), identical locally and in CI.

`just build-sci` (current name) becomes an alias of `just build sci` for back-compat.

## 8. CI workflows

- `ci.yml` (existing) — lean build + `just test` (hermetic) + `just test-net` + lint. Unchanged.
- `toolchain.yml` (new) — build the toolchain image, push to ghcr. Triggered by changes under `Dockerfile` / `sci/{clibs,toolchain,patches}/`. Manual-dispatchable.
- `wheels.yml` (new) — matrix over the `sci` group, build each wheel in the toolchain image, upload to a GitHub Release, regenerate the GH-Pages simple-index. Triggered by version changes in `pyproject.toml` (or manual).
- `sci.yml` (new) — `just build sci` (cross-install + fold) + `just test-sci` + `just test-fs`. Runs on PRs; pulls the published toolchain image + installs wheels from our index. **Not publish-gating for the lean release** (the lean tier remains the CI-blocking gate).

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
- **Hash-pinned / signed wheels** — noted as future hardening; this design pins by exact version.
- **Changing the lean tier** — untouched; it remains the CI-gating, plain-runner build.
- **A WASI PEP-783 equivalent** — doesn't exist; we self-host a PEP 503 index until one does.

## 11. Implementation phasing

This is large; the implementation plan should decompose into independently-verifiable phases, built bottom-up:

1. **Toolchain image** — the `Dockerfile` (wasi-sdk, cross-CPython 3.14.6 + zstd, libc++, patched componentize-py, C-libs). Verify: image builds; a trivial component folds + runs.
2. **Wheel builders + index** — `sci/libs/*/build.sh` producing proper-tagged wheels; publish to a GitHub Release + a PEP 503 GH-Pages index; the `[dependency-groups].sci` set in `pyproject.toml`. Verify: each wheel builds in the image and is `pip`-installable from the index via the `--platform` cross-install.
3. **pyproject-driven bake** — `app.py` sci-import codegen from `[tool.python-env.freeze]`, the cross-install + fold, `just build [lean|sci]`. Verify: `just build sci` installs + folds; `test-sci` + `test-fs` pass; lean unchanged.
4. **CI workflows** — `toolchain.yml`, `wheels.yml`, `sci.yml`. Verify: a clean CI run reproduces the component end-to-end.

Each phase leaves the repo in a working state (lean build never regresses).

## 12. Validation

The build is "reproducible" when, from a clean checkout on a clean machine:
1. `docker build` produces the toolchain image (or `docker pull` the pinned one).
2. `just build lean` and `just build sci` both produce a working component.
3. `just test`, `just test-sci`, `just test-fs` pass.
4. A second run produces a byte-equivalent `python-env.wasm` (modulo any non-determinism in componentize-py/Wizer, which is to be verified and, if present, documented).
