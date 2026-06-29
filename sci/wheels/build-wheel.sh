#!/usr/bin/env bash
# Generic cross-builder: sources libs/$LIB.sh, sets the wasm32-wasip2 cross-
# compilation env, and builds a wheel tagged cp314-cp314-wasi_0_0_0_wasm32.
# Run inside python-env-toolchain:latest with /work mounted to the python-env dir.
#
# Usage: bash sci/wheels/build-wheel.sh <lib>
# Output: /work/dist/<lib>-<ver>-cp314-cp314-wasi_0_0_0_wasm32.whl
#
# libs/<lib>.sh must set/define:
#   LIB_VERSION      – package version string
#   fetch_source()   – downloads + unpacks sdist into $SRC (called with venv active)
#   BUILD_DEPS       – bash array of extra pip deps (e.g. ("Cython>=3") )
#   EXTRA_CFLAGS     – optional string appended to CFLAGS
#   EXTRA_LDFLAGS    – optional string appended to LDFLAGS
#
# Compiler contract: CC=clang, CXX=clang++ (both via include-stripping wrappers).
# C++ extensions link libc++ automatically (clang++ implies it), and $LIBCXX is
# already on the generic link path, so C++ libs need no extra LDFLAGS for libc++.
set -xeuo pipefail

LIB="${1:?usage: build-wheel.sh <lib>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Toolchain paths (inside python-env-toolchain:latest) ──────────────────────
SDK=/opt/wasi-sdk
CROSS=/opt/toolchain/cpython/install          # wasm32-wasip2 Python 3.14 (headers only)
SYSCONFIG_DIR=/opt/toolchain/cpython/sysconfig
PFX=/opt/toolchain/wasi-libs
LIBCXX=/opt/toolchain/build-cxx/lib
TARGET=wasm32-wasip2
export CROSS LIBCXX   # available to lib scripts that need the C++ EH tier

# ── Platform tag: wasi-0.0.0-wasm32 → wheel tag wasi_0_0_0_wasm32 ─────────────
export _PYTHON_HOST_PLATFORM=wasi-0.0.0-wasm32

# ── Host Python 3.14 (produces cp314 ABI tag) ─────────────────────────────────
# The cross Python at $CROSS/bin/python3.14 is a wasm binary; use the native
# build-host Python 3.14 that was compiled during the cpython image stage.
if command -v python3.14 >/dev/null 2>&1; then
  BUILD_PYTHON=$(command -v python3.14)
elif [ -x /opt/toolchain/cpython-src/builddir/build/python ]; then
  BUILD_PYTHON=/opt/toolchain/cpython-src/builddir/build/python
else
  echo "ERROR: No Python 3.14 host binary found." >&2
  echo "  Checked: python3.14 in PATH, /opt/toolchain/cpython-src/builddir/build/python" >&2
  exit 1
fi
echo "### Using build Python: $BUILD_PYTHON ($("$BUILD_PYTHON" --version))"

# ── Bootstrap a venv so pip installs don't pollute system site-packages ────────
VENV_DIR=$(mktemp -d)/venv
"$BUILD_PYTHON" -m venv "$VENV_DIR"
# shellcheck source=/dev/null
. "$VENV_DIR/bin/activate"
python -m pip install -q --upgrade pip

# ── Source lib-specific script ─────────────────────────────────────────────────
# Sets LIB_VERSION, fetch_source(), BUILD_DEPS (array), EXTRA_CFLAGS, EXTRA_LDFLAGS.
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""
BUILD_DEPS=()
source "$SCRIPT_DIR/libs/${LIB}.sh"

# ── Install build dependencies (before sysconfig override) ────────────────────
python -m pip install -q setuptools wheel build "${BUILD_DEPS[@]}"

# ── Fetch source (before cross env — pip must run with native sysconfig) ──────
mkdir -p /work/dist
SRC=$(mktemp -d)
export SRC
fetch_source

# ── Activate cross-target sysconfigdata ───────────────────────────────────────
# This makes `python -m build` pick up the WASM target's compile+link settings.
# Set AFTER pip install so the package manager isn't confused by a foreign sysconfig.
SYSCONFIG_NAME="$(basename "$(ls "$SYSCONFIG_DIR"/_sysconfigdata_*.py | head -1)" .py)"
export _PYTHON_SYSCONFIGDATA_NAME="$SYSCONFIG_NAME"
export PYTHONPATH="$SYSCONFIG_DIR"

# ── CC wrapper: drops host /usr/include* that build backends sometimes inject ──
CCWRAP=$(mktemp /tmp/ccwrap-XXXXXX)
cat > "$CCWRAP" <<WRAP
#!/usr/bin/env bash
final=(); i=1; args=("\$@"); n=\${#args[@]}
while [ \$i -le \$n ]; do
  a="\${args[\$((i-1))]}"
  case "\$a" in
    -I/usr/include|-I/usr/include/*|-I/usr/local/include) i=\$((i+1)); continue;;
    -isystem) nx="\${args[\$i]:-}"; case "\$nx" in /usr/include*|/usr/local/include) i=\$((i+2)); continue;; esac;;
  esac
  final+=("\$a"); i=\$((i+1))
done
exec "$SDK/bin/clang" "\${final[@]}"
WRAP
chmod +x "$CCWRAP"

# ── CXX wrapper: same include-stripping, but execs clang++ so C++ extensions ──
# (numpy Meson backend, Pillow) implicitly link libc++. clang alone would not.
CXXWRAP=$(mktemp /tmp/cxxwrap-XXXXXX)
cat > "$CXXWRAP" <<WRAP
#!/usr/bin/env bash
final=(); i=1; args=("\$@"); n=\${#args[@]}
while [ \$i -le \$n ]; do
  a="\${args[\$((i-1))]}"
  case "\$a" in
    -I/usr/include|-I/usr/include/*|-I/usr/local/include) i=\$((i+1)); continue;;
    -isystem) nx="\${args[\$i]:-}"; case "\$nx" in /usr/include*|/usr/local/include) i=\$((i+2)); continue;; esac;;
  esac
  final+=("\$a"); i=\$((i+1))
done
exec "$SDK/bin/clang++" "\${final[@]}"
WRAP
chmod +x "$CXXWRAP"

# ── LD wrapper: strips host lib refs, allows undefined (resolved at fold time) ─
LDWRAP=$(mktemp /tmp/ldwrap-XXXXXX)
cat > "$LDWRAP" <<WRAP
#!/usr/bin/env bash
out=()
for a in "\$@"; do
  case "\$a" in --start-group|--end-group|/usr/lib/*|/lib/*|-L/usr/lib*|-L/lib/*) ;;
    *) out+=("\$a");; esac
done
exec "$SDK/bin/wasm-ld" "\${out[@]}" --allow-undefined
WRAP
chmod +x "$LDWRAP"
export LDWRAP   # lib scripts that need the C++ EH tier can replace it

# ── Cross-compiler env ─────────────────────────────────────────────────────────
export CC="$CCWRAP"
export CXX="$CXXWRAP"
export AR="$SDK/bin/llvm-ar"
export RANLIB="$SDK/bin/llvm-ranlib"
export CFLAGS="--target=$TARGET -mcpu=lime1 -fPIC -I$PFX/include -I$CROSS/include/python3.14${EXTRA_CFLAGS:+ $EXTRA_CFLAGS}"
export CXXFLAGS="$CFLAGS"
export LDSHARED="$SDK/bin/clang --target=$TARGET -shared -fuse-ld=$LDWRAP"
export LDFLAGS="--target=$TARGET -L$PFX/lib -L$LIBCXX${EXTRA_LDFLAGS:+ $EXTRA_LDFLAGS}"

# ── Build ──────────────────────────────────────────────────────────────────────
cd "$SRC"
echo "### [$(date -u +%H:%M:%S)] cross-building $LIB-${LIB_VERSION} for $TARGET"
python -m build --wheel --no-isolation -o /work/dist

# ── Assert platform tag ────────────────────────────────────────────────────────
WHL=$(ls /work/dist/${LIB}-*-wasi_0_0_0_wasm32.whl 2>/dev/null || true)
if [ -z "$WHL" ]; then
  echo "FAIL: wheel not tagged wasi_0_0_0_wasm32"
  echo "  produced: $(ls /work/dist/${LIB}-*.whl 2>/dev/null || echo '<none>')"
  exit 1
fi
echo "### WHEEL OK: $WHL"
