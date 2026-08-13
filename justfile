wasm := "python-env.wasm"
act := env("ACT", "act")
actbuild := env("ACT_BUILD", "act-build")
act-build := env("ACT_BUILD", "act-build")
registry := env("OCI_REGISTRY", "actpkg.dev/library")

# build the component (lean = pure batteries; sci = + compiled C-ext wheels)
# Pre-req for sci: `dist/` must contain the 8 wasm wheels (run sci/wheels/build-all.sh first).
build variant="lean":
    just build-{{variant}}

# Pyodide-style versioning guard: the version major MUST equal the CPython ABI
# line (314 = CPython 3.14). Run before every build so a CPython minor bump can't
# ship under a stale major — it fails the build and tells you to bump the major.
check-version:
    #!/usr/bin/env bash
    set -euo pipefail
    uv run python - <<'PY'
    import sys, tomllib
    expected = f"{sys.version_info.major}{sys.version_info.minor}"
    version = tomllib.load(open("pyproject.toml", "rb"))["project"]["version"]
    major = version.split(".")[0]
    if major != expected:
        sys.exit(
            f"ERROR: version major ({major}) != CPython ABI cp{expected}. "
            f"Pyodide-style scheme: major = CPython minor. Bump the version to {expected}.0.0."
        )
    print(f"version {version}: major {major} == cp{expected} OK")
    PY

build-lean: check-version
    uv sync --reinstall-package act-sdk
    uv run componentize-py -d wit -w component-world componentize app -o {{wasm}}
    {{act-build}} pack {{wasm}}

# build-sci: folds sci wheels from dist/ + pure deps + app via the toolchain image.
# Requires: dist/*.whl (from sci/wheels/build-all.sh) + docker image python-env-toolchain:latest.
build-sci: check-version
    #!/usr/bin/env bash
    set -euo pipefail
    uv sync --reinstall-package act-sdk
    # In rootless Docker the container's UID 0 already maps to the current host
    # user, so --user is not needed and would break bind-mount access via the
    # subuid namespace.  In rootful Docker --user prevents root-owned output files.
    if docker info 2>/dev/null | grep -q rootless; then
      USER_FLAG=()
    else
      USER_FLAG=(--user "$(id -u):$(id -g)")
    fi
    docker run --rm --network=host \
      "${USER_FLAG[@]}" \
      -v "{{justfile_directory()}}:/work" \
      -w /work \
      python-env-toolchain:latest \
      bash sci/bake/bake-sci.sh
    {{act-build}} pack {{wasm}}

# Hermetic suite: no capability grant, so it also proves install-denied (the
# wasi:http ceiling actually denies with none). net/, fs/ and sci/ have their
# own recipes below — each spawns its own `act --mcp` process per test (see
# e2e/conftest.py), so nothing here needs to spawn or wait on a server itself.
# Rust e2e harness (rmcp client) — replaced the python fastmcp/pytest suite
# (root hermetic directory; net/, fs/ and sci/ subdirectories keep their
# python suites, which need grants or heavy optional builds). Must run from
# inside e2e/: cargo discovers .cargo/config.toml from the CWD, and only
# e2e/'s own config pins the host target.
test:
    cd e2e && ACT="{{act}}" WASM="../{{wasm}}" cargo test

# Makes real HTTPS requests to pypi.org / files.pythonhosted.org — needs
# outbound network from wherever it runs.
test-net:
    ACT="{{act}}" uv run --project e2e pytest e2e/net/ -v

# Filesystem e2e: exec reads/writes data files under a wasi:filesystem grant.
# Separate from the hermetic suite (needs the grant); NOT publish-gating.
# Uses the sci build (C-ext wheels) so fs tests exercise the full tier.
test-fs: build-sci
    ACT="{{act}}" uv run --project e2e pytest e2e/fs/ -v

# e2e for the scientific tier. Builds the sci component via the reproducible
# bake (toolchain image + dist/ wheels) then runs the suite that exercises
# real C-ext packages (numpy, pandas, Pillow, lxml, …) inside the folded component.
test-sci: build-sci
    ACT="{{act}}" uv run --project e2e pytest e2e/sci/ -v

publish:
    #!/usr/bin/env bash
    set -euo pipefail
    INFO=$({{act}} inspect component-manifest {{wasm}})
    NAME=$(echo "$INFO" | jq -r .std.name)
    VERSION=$(echo "$INFO" | jq -r .std.version)
    MAJOR=${VERSION%%.*}   # 314.0.0 -> 314 : the CPython ABI channel (cp314)
    OUTPUT=$({{actbuild}} push {{wasm}} "{{registry}}/$NAME:$VERSION" \
      --skip-if-exists \
      --also-tag latest \
      --also-tag "$MAJOR" 2>&1) || { echo "$OUTPUT" >&2; exit 1; }
    echo "$OUTPUT"
    DIGEST=$(echo "$OUTPUT" | grep "^Digest:" | awk '{print $2}' || true)
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "image={{registry}}/$NAME" >> "$GITHUB_OUTPUT"
      echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
    fi

# Publish the sci variant on its own tag channel: <name>:<version>-sci plus the
# moving `sci` tag (the scientific counterpart of `latest`). Same package + internal
# name as lean — {{wasm}} here is the sci build (just build sci runs first).
publish-sci:
    #!/usr/bin/env bash
    set -euo pipefail
    INFO=$({{act}} inspect component-manifest {{wasm}})
    NAME=$(echo "$INFO" | jq -r .std.name)
    VERSION=$(echo "$INFO" | jq -r .std.version)
    MAJOR=${VERSION%%.*}   # 314.0.0 -> 314 : the CPython ABI channel (cp314), sci variant
    OUTPUT=$({{actbuild}} push {{wasm}} "{{registry}}/$NAME:$VERSION-sci" \
      --skip-if-exists \
      --also-tag sci \
      --also-tag "$MAJOR-sci" 2>&1) || { echo "$OUTPUT" >&2; exit 1; }
    echo "$OUTPUT"
    DIGEST=$(echo "$OUTPUT" | grep "^Digest:" | awk '{print $2}' || true)
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "image={{registry}}/$NAME" >> "$GITHUB_OUTPUT"
      echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
    fi
