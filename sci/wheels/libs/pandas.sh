#!/usr/bin/env bash
# pandas lib descriptor for build-wheel.sh
# Meson C++ build with WASM C++ exceptions; requires WASM numpy headers at
# compile time (Cython buffer dtype: 'q'=int64/longlong, not 'l'=long/x86_64).
# De-localized from build-pandas-eh.sh; paths updated to image layout.
# Sourced by build-wheel.sh (venv active; $SRC, $CROSS, $LIBCXX available).

LIB_VERSION="3.0.3"
BUILD_DEPS=(
  "meson-python>=0.17.1,<1"
  "meson>=1.2.1,<2"
  "Cython>3.1.0,<4.0.0a0"
  "ninja"
  "numpy==2.5.0"
  "versioneer[toml]"
)

# -DNPY_TARGET_VERSION: numpy 2.5.0 ABI compat level (hex); -D__EMSCRIPTEN__=1
# required so pandas skips POSIX-specific code paths (signals, ctypes, etc.)
EXTRA_CFLAGS="-fwasm-exceptions -mllvm -wasm-use-legacy-eh=false -D__EMSCRIPTEN__=1 -DNPY_TARGET_VERSION=0x00000012"

# -nostdlib++: suppress clang's automatic libc++ link; LDWRAP appends PIC+EH libc++
EXTRA_LDFLAGS="-nostdlib++"

# Reuse/regenerate the same meson cross file as numpy
_PANDAS_CROSSFILE=/tmp/wasi-eh-numpy.cross

BUILD_CMD_EXTRA_ARGS=(
  -Cbuild-dir=build
  "-Csetup-args=--cross-file=$_PANDAS_CROSSFILE"
  "-Csetup-args=-Dbuildtype=minsize"
)

fetch_source() {
  # pandas uses meson-python; pip download triggers meson metadata prep which
  # fails without host Python dev headers. Use PyPI JSON API to get the sdist.
  python - "${LIB_VERSION}" "$SRC" <<'PY'
import json, shutil, sys, urllib.request
ver, out_dir = sys.argv[1], sys.argv[2]
data = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/pandas/{ver}/json"))
url = next(u["url"] for u in data["urls"] if u["packagetype"] == "sdist")
out = f"{out_dir}/pandas-{ver}.tar.gz"
print(f"Downloading {url}", flush=True)
with urllib.request.urlopen(url) as r, open(out, "wb") as f:
    shutil.copyfileobj(r, f)
PY
  tar xf "$SRC/pandas-${LIB_VERSION}.tar.gz" -C "$SRC" --strip-components=1
}

# Called by build-wheel.sh after cross env is set, cwd = $SRC.
pre_build_hook() {
  # ── Install patchelf (pandas' build-system.requires; host-only tool) ─────
  (
    unset _PYTHON_HOST_PLATFORM _PYTHON_SYSCONFIGDATA_NAME
    python -m pip install -q "patchelf>=0.11.0"
  )

  local SDK=/opt/wasi-sdk
  local L="$LIBCXX"   # /opt/toolchain/build-cxx/lib
  local RT="$SDK/lib/clang/22/lib/wasm32-unknown-wasip2/libclang_rt.builtins.a"
  local TARGET=wasm32-wasip2

  # ── Meson cross file (same spec as numpy) ────────────────────────────────
  cat > "$_PANDAS_CROSSFILE" <<EOF
[binaries]
c = ['$SDK/bin/clang', '--target=$TARGET', '-mcpu=lime1']
cpp = ['$SDK/bin/clang++', '--target=$TARGET', '-mcpu=lime1']
ar = '$SDK/bin/llvm-ar'
ranlib = '$SDK/bin/llvm-ranlib'
pkgconfig = 'pkg-config'
[properties]
needs_exe_wrapper = true
skip_sanity_check = true
longdouble_format = 'IEEE_QUAD_LE'
[host_machine]
system = 'emscripten'
cpu_family = 'wasm32'
cpu = 'wasm'
endian = 'little'
EOF

  # ── PIC+EH linker wrapper ─────────────────────────────────────────────────
  cat > "$LDWRAP" <<WRAP
#!/usr/bin/env bash
out=()
for a in "\$@"; do
  case "\$a" in
    --start-group|--end-group|/usr/lib/*|/lib/*|-L/usr/lib*|-L/lib/*) ;;
    *) out+=("\$a");;
  esac
done
exec "$SDK/bin/wasm-ld" "\${out[@]}" \
  "$L/libc++.a" "$L/libc++abi.a" "$L/libunwind.a" \
  "$RT" --allow-undefined
WRAP
  chmod +x "$LDWRAP"
  export CC_LD="$LDWRAP"
  export CXX_LD="$LDWRAP"

  # ── Extract WASM numpy headers for cross-compilation ─────────────────────
  # Host numpy (installed for Cython) has int64=long (x86_64); WASM numpy has
  # int64=long long. Cython buffer format 'q' mismatch at runtime otherwise.
  local NUMPY_WASM_DIR
  NUMPY_WASM_DIR=$(mktemp -d)
  local NUMPY_WHL
  NUMPY_WHL=$(ls /work/dist/numpy-*-wasi_0_0_0_wasm32.whl 2>/dev/null | head -1)
  if [ -z "$NUMPY_WHL" ]; then
    echo "ERROR: no WASM numpy wheel found in /work/dist" >&2
    exit 1
  fi
  # Extract using Python zipfile (unzip may not be installed in toolchain image)
  python3 - "$NUMPY_WHL" "$NUMPY_WASM_DIR" <<'PY'
import sys, zipfile
whl, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(whl) as z:
    for name in z.namelist():
        if name.startswith("numpy/_core/include/"):
            z.extract(name, dst)
print(f"Extracted numpy headers to {dst}/numpy/_core/include")
PY
  local NUMPY_INC="$NUMPY_WASM_DIR/numpy/_core/include"
  cd "$SRC"

  # ── Patch 1: guard ctypes imports (WASI CPython has no _ctypes module) ───
  python3 - pandas <<'P1'
import sys, os, re
root = sys.argv[1]
guard = ("try:\n    import ctypes\nexcept ImportError:  # _ctypes absent under WASI\n"
         "    ctypes = None")
n = 0
for dp, _, fns in os.walk(root):
    if "/tests" in dp:
        continue
    for fn in fns:
        if not fn.endswith(".py"):
            continue
        fp = os.path.join(dp, fn)
        s = open(fp).read()
        if re.search(r"(?m)^import ctypes$", s) and "except ImportError:  # _ctypes absent" not in s:
            open(fp, "w").write(re.sub(r"(?m)^import ctypes$", guard, s, count=1))
            n += 1
print(f"guarded ctypes in {n} files")
P1

  # ── Patch 2: hardcode WASM numpy include path in pandas meson.build ──────
  python3 - pandas/meson.build "$NUMPY_INC" <<'P2'
import re, sys
p, npinc = sys.argv[1], sys.argv[2]
s = open(p).read()
if "incdir_numpy = run_command(" in s:
    s2 = re.sub(
        r"incdir_numpy = run_command\(.*?\)\.stdout\(\)\.strip\(\)",
        f"incdir_numpy = '{npinc}'",
        s, count=1, flags=re.S,
    )
    open(p, "w").write(s2)
    print("patched incdir_numpy ->", npinc)
else:
    print("incdir_numpy pattern not found — skipping patch")
P2
}
