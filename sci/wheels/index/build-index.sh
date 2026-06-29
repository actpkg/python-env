#!/usr/bin/env bash
# Build a PEP 503 "simple" index from a directory of wheels.
# Usage: build-index.sh <wheel-dir> <out-dir> [base-url]
#   wheel-dir  directory containing *.whl files
#   out-dir    output root; writes <out-dir>/simple/index.html and
#              <out-dir>/simple/<normalized-name>/index.html
#   base-url   URL prefix for wheel hrefs (default: ../../wheels)
set -euo pipefail
WHEEL_DIR="${1:?wheel dir}"; OUT="${2:?out dir}"; BASE="${3:-../../wheels}"
python3 - "$WHEEL_DIR" "$OUT" "$BASE" <<'PY'
import sys, pathlib, re, html
wheels, out, base = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
def norm(n): return re.sub(r"[-_.]+", "-", n).lower()
by = {}
for w in sorted(wheels.glob("*.whl")):
    proj = norm(w.name.split("-")[0]); by.setdefault(proj, []).append(w.name)
simple = out / "simple"; simple.mkdir(parents=True, exist_ok=True)
(simple / "index.html").write_text(
    "<!DOCTYPE html><html><body>\n" +
    "".join(f'<a href="{p}/">{p}</a><br>\n' for p in sorted(by)) +
    "</body></html>\n"
)
for proj, files in by.items():
    d = simple / proj; d.mkdir(exist_ok=True)
    links = "".join(
        f'<a href="{base}/{html.escape(f)}">{html.escape(f)}</a><br>\n'
        for f in sorted(files)
    )
    (d / "index.html").write_text(
        "<!DOCTYPE html><html><body>\n" + links + "</body></html>\n"
    )
print(f"index for {sorted(by)} -> {simple}")
PY
