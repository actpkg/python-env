#!/usr/bin/env bash
# Upload wheels to a GitHub Release + deploy the PEP 503 /simple/ tree to GH Pages.
# REQUIRES: a python-env-wheels repo with Pages enabled + gh auth. Runs in CI / by the
# maintainer, NOT in the build sandbox.
set -euo pipefail
: "${WHEELS_REPO:?e.g. actpkg/python-env-wheels}"
: "${RELEASE_TAG:?e.g. wheels-2026.06.29}"
WHEEL_DIR="${1:?wheel dir}"
gh release create "$RELEASE_TAG" -R "$WHEELS_REPO" \
    --notes "wasm32-wasip2 cp314 wheels" "$WHEEL_DIR"/*.whl \
  || gh release upload "$RELEASE_TAG" -R "$WHEELS_REPO" \
    "$WHEEL_DIR"/*.whl --clobber
BASE="https://github.com/$WHEELS_REPO/releases/download/$RELEASE_TAG"
bash "$(dirname "$0")/build-index.sh" "$WHEEL_DIR" ./_site "$BASE"
echo "Deploy ./_site/simple to GH Pages (CI: actions/deploy-pages)."
