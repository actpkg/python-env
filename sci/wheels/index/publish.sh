#!/usr/bin/env bash
# Publish wheels + PEP 503 index to the orphan gh-pages branch of THIS repo
# (actpkg/python-env).
#
# gh-pages is an ORPHAN branch — no shared history with main.  It holds only
# generated wheel binaries and the PEP 503 index.  Delete it when PyPI ships
# native WASI wheel support and python-env can install from PyPI directly.
#
# Layout pushed to gh-pages (GH Pages serves at actpkg.github.io/python-env/):
#
#   .nojekyll
#   wheels/<lib>-<ver>-cp314-cp314-wasi_0_0_0_wasm32.whl   (8 wheel binaries)
#   simple/index.html                                        (PEP 503 project list)
#   simple/<normalized-name>/index.html                      (hrefs → ../../wheels/<whl>)
#
# Wheel hrefs are relative (../../wheels/<whl>) so the index is self-contained
# and works both at file:// (local verification) and at the live GH Pages URL.
#
# Index URL: https://actpkg.github.io/python-env/simple/
# Matches [[tool.uv.index]] url in pyproject.toml.
#
# Requirements:
#   - Run from inside the actpkg/python-env git checkout with push credentials
#     (git credential helper, GITHUB_TOKEN, or SSH key).
#   - git and bash must be on PATH.
# This is a CI / maintainer step — do NOT run from a local sandbox (no push auth).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEEL_DIR="${1:-dist}"
[[ -d "$WHEEL_DIR" ]] || { echo "ERROR: wheel dir not found: $WHEEL_DIR" >&2; exit 1; }
WHEEL_DIR="$(cd "$WHEEL_DIR" && pwd)"

# ── Guard: must be inside a git repo with an 'origin' remote ─────────────────
git rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "ERROR: not inside a git repo — run from the python-env checkout" >&2; exit 1; }
ORIGIN="$(git remote get-url origin 2>/dev/null)" \
  || { echo "ERROR: no 'origin' remote configured" >&2; exit 1; }
echo "Publishing wheels to gh-pages of: $ORIGIN"

# ── 1. Build the gh-pages tree in a temp dir ─────────────────────────────────
TREE="$(mktemp -d)"
WORKTREE=""
cleanup() {
    [[ -n "$WORKTREE" && -d "$WORKTREE" ]] \
      && git worktree remove --force "$WORKTREE" 2>/dev/null || true
    rm -rf "$TREE" "${WORKTREE:-}"
}
trap cleanup EXIT

mkdir -p "$TREE/wheels"
cp "$WHEEL_DIR"/*.whl "$TREE/wheels/"
# .nojekyll prevents GH Pages from stripping underscore-prefixed paths
touch "$TREE/.nojekyll"

# Build PEP 503 simple/ index.
# base-url "../../wheels" → hrefs like ../../wheels/<whl>:
#   from simple/<proj>/index.html  →  ../../wheels/<whl>  →  wheels/<whl> at tree root
# Resolves correctly under both file:// (local verify) and GH Pages HTTPS.
bash "$SCRIPT_DIR/build-index.sh" "$TREE/wheels" "$TREE" "../../wheels"

echo "--- gh-pages tree ---"
find "$TREE" -mindepth 1 | sort
echo "---------------------"

# ── 2. Push tree to orphan gh-pages branch via git worktree ──────────────────
WORKTREE="$(mktemp -d)"
rmdir "$WORKTREE"  # git worktree add requires the target path to not exist

# Create a detached-HEAD worktree; then switch it to the gh-pages branch.
# --detach avoids colliding with any existing local 'gh-pages' tracking ref.
git worktree add --detach "$WORKTREE" HEAD

(
    cd "$WORKTREE"

    if git fetch origin gh-pages 2>/dev/null; then
        # gh-pages exists on origin: reset the local branch to the remote tip
        # (we will force-push anyway, but this keeps the commit parent sane)
        git checkout -B gh-pages FETCH_HEAD
    else
        # First publish: create an orphan branch (no parent commits)
        git checkout --orphan gh-pages
    fi

    # Clear the working tree and staging area completely before writing new tree
    git rm -rf . --quiet 2>/dev/null || true

    # Copy generated tree into the worktree
    cp -r "$TREE/." .

    git add -A

    if git diff --cached --quiet; then
        echo "gh-pages: no changes detected, nothing to push."
    else
        git commit -m "chore: publish wasi wheels $(date +%Y-%m-%d)"
        # Force-push: gh-pages is a history-free delivery branch (orphan model).
        # Each publish is a complete, idempotent replacement — no incremental merges.
        git push -f origin gh-pages
        echo "Pushed orphan gh-pages branch. Index live at:"
        echo "  https://actpkg.github.io/python-env/simple/"
    fi
)
