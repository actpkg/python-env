#!/usr/bin/env bash
# Pillow lib descriptor for build-wheel.sh
# Builds Pillow with JPEG + FREETYPE + ZLIB from /opt/toolchain/wasi-libs.
# libjpeg-turbo and freetype2 use setjmp -> modern-EH SjLj flags required.
# The __c_longjmp Tag emitted by these libs is handled at componentize-py
# fold time by the toolchain image's wit-component tag-skip patch.
# De-localized from build-pillow.sh; paths updated to image layout.
# Sourced by build-wheel.sh (venv active; $SRC, $CROSS, $PFX available).

LIB_VERSION="12.2.0"
BUILD_DEPS=("setuptools" "wheel" "pybind11")

# SjLj flags for setjmp-using C libs (libjpeg-turbo, freetype2).
# -D__EMSCRIPTEN__=1 : Pillow's setup.py uses it for platform feature detection.
# -I.../freetype2     : cmake-installed freetype2 headers live under include/freetype2/.
EXTRA_CFLAGS="-mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false -D__EMSCRIPTEN__=1 -I$PFX/include/freetype2"

# Pillow's setup.py discovers C libs via *_ROOT env vars
export ZLIB_ROOT="$PFX"
export JPEG_ROOT="$PFX"
export FREETYPE_ROOT="$PFX"

# Pillow config-settings: enable ZLIB + JPEG + FREETYPE; disable unavailable libs
BUILD_CMD_EXTRA_ARGS=(
  -Cplatform-guessing=disable
  -Czlib=enable
  -Cjpeg=enable
  -Cfreetype=enable
  -Ctiff=disable
  -Clcms=disable
  -Cwebp=disable
  -Cjpeg2000=disable
  -Cimagequant=disable
  -Cxcb=disable
  -Cavif=disable
  -Craqm=disable
  -Cfribidi=disable
  -Charfbuzz=disable
)

fetch_source() {
  python -m pip download --no-binary pillow --no-deps "Pillow==${LIB_VERSION}" -d "$SRC"
  tar xf "$SRC"/pillow-*.tar.gz -C "$SRC" --strip-components=1
}

# Called by build-wheel.sh after cross env is set, cwd = $SRC.
pre_build_hook() {
  local SDK=/opt/wasi-sdk
  local SETJMP_LIB="$SDK/share/wasi-sysroot/lib/wasm32-wasip2/libsetjmp.a"

  # Replace generic LDWRAP with one that appends libsetjmp.a, which provides
  # the SjLj runtime (__wasm_setjmp/__wasm_longjmp) needed by libjpeg-turbo
  # and freetype2. Without it the linker can't resolve the setjmp symbols.
  cat > "$LDWRAP" <<WRAP
#!/usr/bin/env bash
out=()
for a in "\$@"; do
  case "\$a" in
    --start-group|--end-group|/usr/lib/*|/lib/*|-L/usr/lib*|-L/lib/*) ;;
    *) out+=("\$a");;
  esac
done
exec "$SDK/bin/wasm-ld" "\${out[@]}" "$SETJMP_LIB" --allow-undefined
WRAP
  chmod +x "$LDWRAP"

  # Pillow's setup.py has a platform-guessing path that appends host /usr/include*
  # even when -Cplatform-guessing=disable is passed as a config-setting (the
  # -C flags aren't always forwarded reliably under --no-isolation). Patch it
  # directly so disable_platform_guessing=True for all code paths.
  if grep -q 'self.disable_platform_guessing = self.check_configuration(' setup.py; then
    sed -i 's/self.disable_platform_guessing = self.check_configuration(/self.disable_platform_guessing = True or self.check_configuration(/' setup.py
  fi
}
