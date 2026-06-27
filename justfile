wasm := "python-env.wasm"
act := env("ACT", "act")
actbuild := env("ACT_BUILD", "act-build")
act-build := env("ACT_BUILD", "act-build")
hurl := env("HURL", "hurl")
registry := env("OCI_REGISTRY", "actpkg.dev/library")
# Scientific (numpy) tier uses the patched wasm-EH toolchain (build scripts:
# act-context/docs/specs/2026-06-27-python-env-phase3-toolchain/). Built/tested
# locally, NOT in CI. Override SCI_TOOLCHAIN if it lives elsewhere.
sci-toolchain := env("SCI_TOOLCHAIN", justfile_directory() / "../../.sci-toolchain")
patched-cpy := sci-toolchain / "componentize-py-eh"
numpy-pkg := sci-toolchain / "numpy-eh-pkg"
pandas-pkg := sci-toolchain / "pandas-eh-pkg"
regex-pkg := sci-toolchain / "regex-pkg"
msgpack-pkg := sci-toolchain / "msgpack-pkg"
lxml-pkg := sci-toolchain / "lxml-pkg"
lz4-pkg := sci-toolchain / "lz4-pkg"
pillow-pkg := sci-toolchain / "pillow-pkg"
# Random port for the e2e server, in a safe range: above the well-known/common
# dev ports and below the Linux outbound ephemeral range (32768+).
port := `shuf -i 10000-29999 -n 1`
addr := "[::1]:" + port
baseurl := "http://" + addr

build:
    uv sync --reinstall-package act-sdk
    uv run componentize-py -d wit -w component-world componentize app -o {{wasm}}
    {{act-build}} pack {{wasm}}

test:
    #!/usr/bin/env bash
    set -euo pipefail
    {{act}} run {{wasm}} --http --listen "{{addr}}" --session-args '{}' &
    trap "kill $!" EXIT
    curl --retry 240 --retry-connrefused --retry-delay 1 -fs -o /dev/null {{baseurl}}/info
    {{hurl}} --test --variable "baseurl={{baseurl}}" e2e/*.hurl

test-net:
    #!/usr/bin/env bash
    set -euo pipefail
    {{act}} run {{wasm}} --http --listen "{{addr}}" --session-args '{}' --allow wasi:http &
    trap "kill $!" EXIT
    curl --retry 240 --retry-connrefused --retry-delay 1 -fs -o /dev/null {{baseurl}}/info
    {{hurl}} --test --variable "baseurl={{baseurl}}" e2e/net/*.hurl

# Full "Pyodide-via-ACT" build: python-env WITH the scientific tier (numpy 2.5.0
# + pandas 3.0.3) folded in, via the patched wasm-EH componentize-py. Requires the
# local toolchain (SCI_TOOLCHAIN) and a wasm-EH-enabled act at runtime. The lean
# `build` stays CI-buildable; this one is built locally. WASI-absent stdlib shims
# (ctypes/bz2/lzma/mmap) live in _wasi_compat.py and apply to both builds.
# See act-context/docs/specs/2026-06-27-python-env-phase3-toolchain/.
build-sci:
    uv sync --reinstall-package act-sdk
    {{patched-cpy}} -d wit -w component-world componentize \
      -p .venv/lib/python3.14/site-packages -p {{numpy-pkg}} -p {{pandas-pkg}} -p {{regex-pkg}} -p {{pillow-pkg}} -p {{msgpack-pkg}} -p {{lxml-pkg}} -p {{lz4-pkg}} -p . \
      -o {{wasm}} app
    {{act-build}} pack {{wasm}}

# e2e for the scientific tier. Needs `just build-sci` first AND a wasm-EH act:
#   ACT=/path/to/wasm-eh/act just test-sci
test-sci:
    #!/usr/bin/env bash
    set -euo pipefail
    {{act}} run {{wasm}} --http --listen "{{addr}}" --session-args '{}' &
    trap "kill $!" EXIT
    curl --retry 240 --retry-connrefused --retry-delay 1 -fs -o /dev/null {{baseurl}}/info
    {{hurl}} --test --variable "baseurl={{baseurl}}" e2e/sci/*.hurl

publish:
    #!/usr/bin/env bash
    set -euo pipefail
    INFO=$({{act}} inspect component-manifest {{wasm}})
    NAME=$(echo "$INFO" | jq -r .std.name)
    VERSION=$(echo "$INFO" | jq -r .std.version)
    OUTPUT=$({{actbuild}} push {{wasm}} "{{registry}}/$NAME:$VERSION" \
      --skip-if-exists \
      --also-tag latest 2>&1) || { echo "$OUTPUT" >&2; exit 1; }
    echo "$OUTPUT"
    DIGEST=$(echo "$OUTPUT" | grep "^Digest:" | awk '{print $2}' || true)
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "image={{registry}}/$NAME" >> "$GITHUB_OUTPUT"
      echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
    fi
