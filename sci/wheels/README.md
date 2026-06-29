# sci-wheels — WASI cp314 wheel build pipeline

Pre-built `cp314-cp314-wasi_0_0_0_wasm32` wheels for the eight scientific
libraries in the `[dependency-groups].sci` group of `pyproject.toml`.

The wheels are wasm32-wasip2 binaries produced by cross-compiling each library's
C extensions against the WASI SDK and a statically-configured CPython 3.14 header
tree.  They **cannot** run natively — they are folded into the component at bake
time by `componentize-py`.

---

## Directory layout

```
sci/wheels/
  build-wheel.sh        # Per-lib builder (runs in the toolchain image)
  build-all.sh          # Driver: builds all 8 libs + generates the index
  libs/                 # One <lib>.sh per library (build instructions)
  index/
    build-index.sh      # PEP 503 simple/ index generator
    publish.sh          # GH-Release + GH-Pages publish (CI / maintainer)
```

---

## Building one wheel

Requires the `python-env-toolchain:latest` Docker image (built from
`sci/toolchain/`).

```bash
# from the repo root (act/):
docker run --rm --network=host \
  -v "$PWD/components/python-env:/work" -w /work \
  python-env-toolchain:latest \
  bash sci/wheels/build-wheel.sh <lib>
```

`<lib>` must match a file in `libs/` (lowercase).  Output goes to
`dist/<lib>-<ver>-cp314-cp314-wasi_0_0_0_wasm32.whl`.

### Proper-tag requirement

Every wheel must carry the tag `cp314-cp314-wasi_0_0_0_wasm32`; `build-wheel.sh`
asserts this and exits non-zero if the tag is wrong.  The tag is produced by
setting `_PYTHON_HOST_PLATFORM=wasi-0.0.0-wasm32` before calling `python -m
build` with the native CPython 3.14 host.  Do not use `any` or `none-any` wheels
— `componentize-py`'s bake step requires the platform-tagged wheel to locate the
compiled `.so` files.

---

## Building all 8 wheels at once

```bash
# from the repo root (act/):
docker run --rm --network=host \
  -v "$PWD/components/python-env:/work" -w /work \
  python-env-toolchain:latest \
  bash sci/wheels/build-all.sh
```

`build-all.sh`:
1. Reads the `[dependency-groups].sci` list from `pyproject.toml` (single source
   of truth for lib names + versions).
2. Puts `numpy` first — `pandas` and `bottleneck` compile against numpy's headers
   and must see it in `dist/` before their own builds start.
3. Calls `build-wheel.sh <lib>` for each lib in order.
4. Generates `dist/_site/simple/` with `index/build-index.sh` pointing hrefs at
   `file://$PWD/dist` (suitable for a local `pip install --index-url`).

After the run, `dist/` contains 8 wheels and `dist/_site/simple/` holds the PEP
503 index.

### Verifying the output

```bash
# count wasi-tagged wheels — expect 8
ls components/python-env/dist/*-cp314-cp314-wasi_0_0_0_wasm32.whl | wc -l

# cross-install the whole group (the exact mechanism Phase 3 bakes with)
bash sci/wheels/index/build-index.sh \
  components/python-env/dist /tmp/idx-all \
  "file://$PWD/components/python-env/dist"

python3.14 -m pip install \
  --platform wasi_0_0_0_wasm32 --python-version 3.14 \
  --target /tmp/sci-all --only-binary=:all: --no-deps \
  --index-url "file:///tmp/idx-all/simple/" \
  numpy pandas regex Pillow msgpack lxml lz4 bottleneck

ls /tmp/sci-all | sort   # expect 8 package dirs + 8 dist-info dirs
```

---

## Publishing (CI / maintainer step)

Publishing requires:
- A `python-env-wheels` GitHub repository with GitHub Pages enabled.
- `gh` authenticated with a PAT that has `contents:write` and `pages:write`.
- The `WHEELS_REPO` and `RELEASE_TAG` environment variables set.

```bash
export WHEELS_REPO=actpkg/python-env-wheels
export RELEASE_TAG=wheels-$(date +%Y.%m.%d)

bash sci/wheels/index/publish.sh components/python-env/dist
```

`publish.sh`:
1. Creates (or updates) a GitHub Release tagged `$RELEASE_TAG` and uploads the 8
   `.whl` files as release assets.
2. Calls `build-index.sh` with the GitHub Release download URL as `base-url` so
   wheel hrefs point at the release assets, not at local paths.
3. Outputs the `_site/` tree (containing `_site/simple/`). Deploy **`_site/`**
   (not `_site/simple/`) to GitHub Pages via `actions/deploy-pages` (`path: ./_site`)
   so the index is served at `<pages-url>/simple/` — matching the
   `[[tool.uv.index]]` url in `pyproject.toml`. Deploying `_site/simple/` as the
   Pages root would 404 the `/simple/` lookup.

This is a **maintainer / CI step**.  Do not run it from a local sandbox — it
requires network access to GitHub.
