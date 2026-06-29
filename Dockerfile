# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS base
ARG WASI_SDK_VER=33.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git build-essential cmake ninja-build \
      python3 python3-venv python3-pip pkg-config patch \
      libssl-dev zlib1g-dev libffi-dev \
 && rm -rf /var/lib/apt/lists/*
# pinned wasi-sdk
RUN curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VER%%.*}/wasi-sdk-${WASI_SDK_VER}-x86_64-linux.tar.gz" \
      | tar xz -C /opt && ln -s /opt/wasi-sdk-${WASI_SDK_VER}-x86_64-linux /opt/wasi-sdk
# Rust (for componentize-py), meson (for numpy/pandas/contourpy)
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"
RUN pip install --break-system-packages meson
WORKDIR /opt/toolchain

# ---------------------------------------------------------------------------
# cpython: cross-built wasm32-wasip2 CPython 3.14.6 dev environment
#   (libpython3.14.so + headers + sysconfigdata) staged at
#   /opt/toolchain/cpython/{install,sysconfig}. Built from upstream
#   python/cpython v3.14.6 against the base's /opt/wasi-sdk (33) -- single SDK,
#   no wasi-wheels build dependency (see build-cpython.sh header).
# ---------------------------------------------------------------------------
FROM base AS cpython
COPY sci/patches /opt/toolchain/sci/patches
COPY sci/toolchain/build-cpython.sh /tmp/build-cpython.sh
RUN bash /tmp/build-cpython.sh

# ---------------------------------------------------------------------------
# libcxx: PIC + exception-handling libc++ / libc++abi / libunwind
#   Built against wasi-sdk 33 (base's /opt/wasi-sdk, clang 22) for modern
#   try_table EH support (-fwasm-exceptions). Archives staged at:
#     /opt/toolchain/build-cxx/lib/{libc++.a,libc++abi.a,libunwind.a}
#   Pinned to LLVM 4434dabb6991 (22.1.0), the revision wasi-sdk 33 ships.
# ---------------------------------------------------------------------------
FROM cpython AS libcxx
COPY sci/toolchain/build-libcxx-piceh.sh /tmp/build-libcxx.sh
RUN bash /tmp/build-libcxx.sh

# ---------------------------------------------------------------------------
# componentize: patched componentize-py built from source
#   wit-component-0.245.1-skip-tag-export.patch: adds ExternalKind::Tag => continue
#   in the shared-everything linker so C extensions that use setjmp (freetype,
#   libjpeg) can be folded without "unsupported export kind for __c_longjmp: Tag".
#   Pin: v0.24.0 = 811ff834f1d6 (known-good: folds all sci C-extension packages)
#   Binary staged at /opt/toolchain/bin/componentize-py.
# ---------------------------------------------------------------------------
FROM libcxx AS componentize
ARG COMPONENTIZE_PY_REF=811ff834f1d6
COPY sci/patches/ /opt/toolchain/patches/
COPY sci/toolchain/build-componentize-py.sh /tmp/build-componentize-py.sh
RUN COMPONENTIZE_PY_REF="${COMPONENTIZE_PY_REF}" bash /tmp/build-componentize-py.sh
ENV PATH="/opt/toolchain/bin:${PATH}"

# ---------------------------------------------------------------------------
# clibs: C libraries cross-built for wasm32-wasip2 into /opt/toolchain/wasi-libs
#   zlib 1.3.1, libjpeg-turbo 3.0.4, freetype 2.13.3, libxml2 2.13.5, libxslt 1.1.42
#   setjmp libs (libjpeg, freetype) built with modern-EH SjLj:
#     -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false
#   This is the final toolchain image; downstream sci builds link against
#   /opt/toolchain/wasi-libs/{include,lib} when compiling C-extension wheels.
# ---------------------------------------------------------------------------
FROM componentize AS clibs
COPY sci/clibs/build-clibs.sh /tmp/build-clibs.sh
RUN bash /tmp/build-clibs.sh
