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

Wheels and the PEP 503 index live together on an **orphan `gh-pages` branch** of
the `actpkg/python-env` repository — no separate repo, no GitHub Releases.
The branch has no shared history with `main`; it holds only generated binaries
and the index.  Delete it when PyPI adds native WASI wheel support.

GH Pages serves the branch root at `https://actpkg.github.io/python-env/`, giving:

```
.nojekyll
wheels/<lib>-<ver>-cp314-cp314-wasi_0_0_0_wasm32.whl
simple/index.html
simple/<normalized-name>/index.html   ← hrefs → ../../wheels/<whl>  (relative)
```

The index is served at `https://actpkg.github.io/python-env/simple/`, matching
the `[[tool.uv.index]]` url in `pyproject.toml`.

Publishing requires push credentials to `actpkg/python-env` (SSH key, GITHUB_TOKEN,
or a git credential helper).  No `gh` CLI, no `WHEELS_REPO`, no `RELEASE_TAG`.

```bash
# from the repo root (act/components/python-env):
bash sci/wheels/index/publish.sh dist
```

`publish.sh`:
1. Copies `dist/*.whl` into `wheels/` inside a temp tree and adds `.nojekyll`.
2. Calls `build-index.sh dist/ <tree> "../../wheels"` to generate `simple/` with
   relative hrefs (`../../wheels/<whl>`) that resolve correctly at both `file://`
   (local verification) and the live GH Pages HTTPS URL.
3. Checks out (or creates) the orphan `gh-pages` branch via `git worktree add`,
   replaces its entire content with the new tree, commits, and
   **force-pushes** (`git push -f origin gh-pages`) — force-push is the correct
   model for a history-free delivery branch.

This is a **maintainer / CI step**.  Do not run it from a local sandbox — it
requires push access to GitHub.
