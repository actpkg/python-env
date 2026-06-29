wasm := "python-env.wasm"
act := env("ACT", "act")
actbuild := env("ACT_BUILD", "act-build")
act-build := env("ACT_BUILD", "act-build")
hurl := env("HURL", "hurl")
registry := env("OCI_REGISTRY", "actpkg.dev/library")
# Random port for the e2e server, in a safe range: above the well-known/common
# dev ports and below the Linux outbound ephemeral range (32768+).
port := `shuf -i 10000-29999 -n 1`
addr := "[::1]:" + port
baseurl := "http://" + addr

# build the component (lean = pure batteries; sci = + compiled C-ext wheels)
# Pre-req for sci: `dist/` must contain the 8 wasm wheels (run sci/wheels/build-all.sh first).
build variant="lean":
    just build-{{variant}}

build-lean:
    uv sync --reinstall-package act-sdk
    uv run componentize-py -d wit -w component-world componentize app -o {{wasm}}
    {{act-build}} pack {{wasm}}

# build-sci: folds sci wheels from dist/ + pure deps + app via the toolchain image.
# Requires: dist/*.whl (from sci/wheels/build-all.sh) + docker image python-env-toolchain:latest.
build-sci:
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

# Filesystem e2e: exec reads/writes data files under a wasi:filesystem grant.
# Separate from the hermetic suite (needs the grant); NOT publish-gating.
# Uses the sci build (C-ext wheels) so fs tests exercise the full tier.
test-fs: build-sci
    #!/usr/bin/env bash
    set -euo pipefail
    {{act}} run {{wasm}} --http --listen "{{addr}}" --session-args '{}' --allow wasi:filesystem &
    trap "kill $!" EXIT
    curl --retry 240 --retry-connrefused --retry-delay 1 -fs -o /dev/null {{baseurl}}/info
    {{hurl}} --test --variable "baseurl={{baseurl}}" e2e/fs/*.hurl

# e2e for the scientific tier. Builds the sci component via the reproducible
# bake (toolchain image + dist/ wheels) then runs the hurl suite that exercises
# real C-ext packages (numpy, pandas, Pillow, lxml, …) inside the folded component.
test-sci: build-sci
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
