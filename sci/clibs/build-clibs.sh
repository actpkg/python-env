#!/usr/bin/env bash
# build-clibs.sh — cross-build C libraries for wasm32-wasip2 sci tier
# Output prefix: /opt/toolchain/wasi-libs
# Libs: zlib 1.3.1, libjpeg-turbo 3.0.4, freetype 2.13.3, libxml2 2.13.5, libxslt 1.1.42
# setjmp libs (libjpeg, freetype) use modern-EH SjLj:
#   -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false
set -xeuo pipefail

SDK=/opt/wasi-sdk
PFX=/opt/toolchain/wasi-libs
mkdir -p "$PFX"
TC="$SDK/share/cmake/wasi-sdk-p2.cmake"
# Modern-EH SjLj flags (NOT deprecated legacy-exceptions path)
SJLJ="-mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false"

cd /opt/toolchain
mkdir -p src
cd src

# ---------------------------------------------------------------------------
# zlib 1.3.1  ->  libz.a
# ---------------------------------------------------------------------------
curl -fsSL https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz | tar xz
cmake -S zlib-1.3.1 -B b-zlib \
  -DCMAKE_TOOLCHAIN_FILE="$TC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX="$PFX" \
  -DCMAKE_C_FLAGS="-fPIC -mcpu=lime1" \
  -DZLIB_BUILD_EXAMPLES=OFF
cmake --build b-zlib --target install
# zlib 1.3.1's CMakeLists builds the `zlib` SHARED target unconditionally
# (no BUILD_SHARED_LIBS/ZLIB_BUILD_SHARED knob), so it always installs a
# libzlib.so. WASI has no dynamic linking — drop the dead shared object and
# keep only the static archive, exposed under the canonical name libz.a.
rm -f "$PFX/lib/"libzlib.so*
cp "$PFX/lib/libzlibstatic.a" "$PFX/lib/libz.a"

# ---------------------------------------------------------------------------
# libjpeg-turbo 3.0.4  (uses setjmp)  ->  libjpeg.a
# ---------------------------------------------------------------------------
curl -fsSL https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.0.4/libjpeg-turbo-3.0.4.tar.gz | tar xz
cmake -S libjpeg-turbo-3.0.4 -B b-jpeg \
  -DCMAKE_TOOLCHAIN_FILE="$TC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX="$PFX" \
  -DENABLE_SHARED=OFF \
  -DWITH_SIMD=OFF \
  -DCMAKE_C_FLAGS="-fPIC -mcpu=lime1 $SJLJ"
cmake --build b-jpeg || true   # example exe link may fail; grab the lib directly
cp b-jpeg/libjpeg.a "$PFX/lib/"
mkdir -p "$PFX/include"
cp libjpeg-turbo-3.0.4/jpeglib.h libjpeg-turbo-3.0.4/jmorecfg.h "$PFX/include/"
# jconfig.h is generated into the build directory
cp b-jpeg/jconfig.h "$PFX/include/" 2>/dev/null || cp libjpeg-turbo-3.0.4/jconfig*.h "$PFX/include/" 2>/dev/null || true

# ---------------------------------------------------------------------------
# freetype 2.13.3  (uses setjmp)  ->  libfreetype.a + freetype2.pc
# Use freedesktop GitLab directly (Savannah mirrors are unreliable from CI).
# The archive extracts to freetype-VER-2-13-3/ — rename to canonical name.
# ---------------------------------------------------------------------------
curl -fsSL https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-2-13-3/freetype-VER-2-13-3.tar.gz \
  | tar xz --transform='s|^freetype-VER-2-13-3|freetype-2.13.3|'
cmake -S freetype-2.13.3 -B b-ft \
  -DCMAKE_TOOLCHAIN_FILE="$TC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX="$PFX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="-fPIC -mcpu=lime1 $SJLJ -I$PFX/include" \
  -DFT_DISABLE_HARFBUZZ=ON \
  -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_BROTLI=ON \
  -DFT_DISABLE_BZIP2=ON \
  -DFT_REQUIRE_ZLIB=ON \
  -DZLIB_LIBRARY="$PFX/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$PFX/include"
cmake --build b-ft --target install

# ---------------------------------------------------------------------------
# libxml2 2.13.5  ->  libxml2.a + libxml-2.0.pc
# Use GNOME GitLab directly (download.gnome.org slow; codeload.github.com blocked from CI).
# Archive extracts to libxml2-v2.13.5/ — rename to canonical name.
# ---------------------------------------------------------------------------
curl -fsSL https://gitlab.gnome.org/GNOME/libxml2/-/archive/v2.13.5/libxml2-v2.13.5.tar.gz \
  | tar xz --transform='s|^libxml2-[^/]*/|libxml2-2.13.5/|'
cmake -S libxml2-2.13.5 -B b-xml2 \
  -DCMAKE_TOOLCHAIN_FILE="$TC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX="$PFX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="-fPIC -mcpu=lime1 -Wno-implicit-function-declaration -I$PFX/include" \
  -DLIBXML2_WITH_LZMA=OFF \
  -DLIBXML2_WITH_ICONV=OFF \
  -DLIBXML2_WITH_PYTHON=OFF \
  -DLIBXML2_WITH_HTTP=OFF \
  -DLIBXML2_WITH_THREADS=OFF \
  -DLIBXML2_WITH_ZLIB=ON \
  -DLIBXML2_WITH_PROGRAMS=OFF \
  -DBUILD_TESTING=OFF \
  -DZLIB_LIBRARY="$PFX/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$PFX/include"
cmake --build b-xml2 --target LibXml2   # only the library; runtest/xmllint use dup (undefined on WASI)
cmake --install b-xml2

# ---------------------------------------------------------------------------
# libxslt 1.1.42  ->  libxslt.a + libexslt.a + libxslt.pc
# Use GNOME GitLab directly (download.gnome.org slow; codeload.github.com blocked from CI).
# Archive extracts to libxslt-v1.1.42/ — rename to canonical name.
# ---------------------------------------------------------------------------
curl -fsSL https://gitlab.gnome.org/GNOME/libxslt/-/archive/v1.1.42/libxslt-v1.1.42.tar.gz \
  | tar xz --transform='s|^libxslt-[^/]*/|libxslt-1.1.42/|'
cmake -S libxslt-1.1.42 -B b-xslt \
  -DCMAKE_TOOLCHAIN_FILE="$TC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX="$PFX" \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_C_FLAGS="-fPIC -mcpu=lime1 -Wno-implicit-function-declaration -I$PFX/include -I$PFX/include/libxml2" \
  -DLIBXSLT_WITH_PYTHON=OFF \
  -DLIBXSLT_WITH_CRYPTO=OFF \
  -DLIBXSLT_WITH_THREADS=OFF \
  -DLIBXSLT_WITH_PROGRAMS=OFF \
  -DBUILD_TESTING=OFF \
  -DLibXml2_DIR="$PFX/lib/cmake/libxml2-2.13.5" \
  -DLIBXML2_LIBRARY="$PFX/lib/libxml2.a" \
  -DLIBXML2_INCLUDE_DIR="$PFX/include/libxml2" \
  -DZLIB_LIBRARY="$PFX/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$PFX/include"
cmake --build b-xslt --target LibXslt --target LibExslt   # only libs; xsltproc uses dup (undefined on WASI)
cmake --install b-xslt

echo "=== wasi-libs build complete ==="
ls "$PFX/lib/"
