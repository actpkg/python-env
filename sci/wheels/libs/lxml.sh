#!/usr/bin/env bash
# lxml lib descriptor for build-wheel.sh
# Cython->C build; links libxml2 + libxslt + libexslt + libz from
# /opt/toolchain/wasi-libs. No C++ exceptions, no setjmp -> folds cleanly.
# dup/dup2 stub: libxml2 references dup() for fd-based error output; WASI
# component model has no foldable dup (fd_renumber is not componentize-py
# foldable). A weak stub is compiled and linked in so the symbol is defined
# in the wheel itself, returning ENOSYS for the rare error-output path.
# De-localized from build-lxml.sh; paths updated to image layout.
# Sourced by build-wheel.sh (venv active; $SRC, $CROSS, $PFX available).

LIB_VERSION="6.1.1"
BUILD_DEPS=("Cython>=3" "setuptools" "wheel")

# libxml2 headers are installed under include/libxml2/ by cmake.
# -Wno-implicit-function-declaration: libxml2/libxslt use some POSIX calls
# not declared in WASI headers (they won't be called at runtime).
EXTRA_CFLAGS="-I$PFX/include/libxml2 -Wno-implicit-function-declaration"

# Tell lxml where to find libxml2 + libxslt (via the config scripts we write
# in pre_build_hook, or via pkg-config if the scripts are already installed).
BUILD_CMD_EXTRA_ARGS=(
  "-C--build-option=--with-xml2-config=$PFX/bin/xml2-config"
  "-C--build-option=--with-xslt-config=$PFX/bin/xslt-config"
)

fetch_source() {
  # pip download triggers lxml's build metadata (checks for libxml2/libxslt);
  # bypass by fetching the sdist directly from the PyPI JSON API.
  python - "${LIB_VERSION}" "$SRC" <<'PY'
import json, shutil, sys, urllib.request
ver, out_dir = sys.argv[1], sys.argv[2]
data = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/lxml/{ver}/json"))
url = next(u["url"] for u in data["urls"] if u["packagetype"] == "sdist")
out = f"{out_dir}/lxml-{ver}.tar.gz"
print(f"Downloading {url}", flush=True)
with urllib.request.urlopen(url) as r, open(out, "wb") as f:
    shutil.copyfileobj(r, f)
PY
  tar xf "$SRC/lxml-${LIB_VERSION}.tar.gz" -C "$SRC" --strip-components=1
}

# Called by build-wheel.sh after cross env is set, cwd = $SRC.
pre_build_hook() {
  local SDK=/opt/wasi-sdk
  local TARGET=wasm32-wasip2

  # ── pkg-config path ────────────────────────────────────────────────────────
  # cmake-installed libxml2/libxslt put their .pc files under lib/pkgconfig/.
  export PKG_CONFIG_PATH="$PFX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

  # ── xml2-config / xslt-config wrappers ────────────────────────────────────
  # cmake-installed libxml2/libxslt don't generate the autotools *-config
  # scripts; write minimal wrappers so lxml's --with-*-config options work.
  if [ ! -x "$PFX/bin/xml2-config" ]; then
    mkdir -p "$PFX/bin"
    cat > "$PFX/bin/xml2-config" <<CFG
#!/bin/sh
case "\$1" in
  --cflags)  echo "-I$PFX/include/libxml2" ;;
  --libs)    echo "-L$PFX/lib -lxml2 -lz" ;;
  --version) echo "2.13.5" ;;
  *)         echo "-I$PFX/include/libxml2" ;;
esac
CFG
    chmod +x "$PFX/bin/xml2-config"
  fi

  if [ ! -x "$PFX/bin/xslt-config" ]; then
    cat > "$PFX/bin/xslt-config" <<CFG
#!/bin/sh
case "\$1" in
  --cflags)  echo "-I$PFX/include" ;;
  --libs)    echo "-L$PFX/lib -lxslt -lexslt -lxml2 -lz" ;;
  --version) echo "1.1.42" ;;
  *)         echo "-I$PFX/include" ;;
esac
CFG
    chmod +x "$PFX/bin/xslt-config"
  fi

  # ── dup/dup2 stub ──────────────────────────────────────────────────────────
  # libxml2 calls dup()/dup2() in file-descriptor error-output paths. The WASI
  # component model has no equivalent that componentize-py can fold. A weak
  # stub compiled for wasm32-wasip2 is appended to each link so the symbol
  # lives in the wheel and returns ENOSYS if called (the fd-output path is not
  # exercised by normal lxml usage from Python).
  local DUP_SRC; DUP_SRC=$(mktemp /tmp/dup_stub_XXXXXX.c)
  cat > "$DUP_SRC" <<'C'
/* dup/dup2 stub for WASI wasm32-wasip2: libxml2 error-output path only */
#include <errno.h>
__attribute__((weak)) int dup(int fd)
    { (void)fd; errno = 38 /* ENOSYS */; return -1; }
__attribute__((weak)) int dup2(int fd, int fd2)
    { (void)fd; (void)fd2; errno = 38 /* ENOSYS */; return -1; }
C
  local DUP_OBJ; DUP_OBJ=$(mktemp /tmp/dup_stub_XXXXXX.o)
  "$SDK/bin/clang" --target="$TARGET" -mcpu=lime1 -fPIC -c "$DUP_SRC" -o "$DUP_OBJ"

  # Replace generic LDWRAP to append the dup stub to every link command.
  cat > "$LDWRAP" <<WRAP
#!/usr/bin/env bash
out=()
for a in "\$@"; do
  case "\$a" in --start-group|--end-group|/usr/lib/*|/lib/*|-L/usr/lib*|-L/lib/*) ;;
    *) out+=("\$a");; esac
done
exec "$SDK/bin/wasm-ld" "\${out[@]}" "$DUP_OBJ" --allow-undefined
WRAP
  chmod +x "$LDWRAP"
}
