wasm := "python-env.wasm"
act := env("ACT", "act")
act-build := env("ACT_BUILD", "act-build")
hurl := env("HURL", "hurl")
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
    curl --retry 60 --retry-connrefused --retry-delay 1 -fsS -o /dev/null {{baseurl}}/info
    {{hurl}} --test --variable "baseurl={{baseurl}}" e2e/*.hurl
