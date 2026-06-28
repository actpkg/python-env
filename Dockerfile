# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS base
ARG WASI_SDK_VER=33.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git build-essential cmake ninja-build \
      python3 python3-venv python3-pip pkg-config patch \
 && rm -rf /var/lib/apt/lists/*
# pinned wasi-sdk
RUN curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VER%%.*}/wasi-sdk-${WASI_SDK_VER}-x86_64-linux.tar.gz" \
      | tar xz -C /opt && ln -s /opt/wasi-sdk-${WASI_SDK_VER}-x86_64-linux /opt/wasi-sdk
# Rust (for componentize-py), meson (for numpy/pandas/contourpy)
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"
RUN pip install --break-system-packages meson
WORKDIR /opt/toolchain
