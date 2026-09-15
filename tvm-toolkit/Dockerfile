# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

# Packages the host TVM build (lib .so + python/tvm); version comes from the host,
# not hard-coded here (see build-image.sh / _tvm-version.sh). ubuntu:24.04 to match
# the build host's glibc/libstdc++.
FROM ubuntu:24.04

# Version-coupled deps: LLVM_VERSION = matching libLLVM major (TVM codegen),
# TVM_FFI_VERSION = apache-tvm-ffi bundled in this TVM.
ARG LLVM_VERSION=18
ARG TVM_FFI_VERSION=0.1.11

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python-is-python3 libstdc++6 libgomp1 ca-certificates \
        libllvm${LLVM_VERSION} \
        gcc g++ \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
    && rm -rf /var/lib/apt/lists/*
# native gcc/g++ let export_library link the host (x86_64) model.so; without them get_cc()=None → link fails.
# cross-toolchains for aarch64 + armhf targets (binutils rides in as a hard dep of each g++-*).

COPY lib/ /opt/tvm/lib/
COPY python/ /opt/tvm/python/

ENV LD_LIBRARY_PATH=/opt/tvm/lib \
    PYTHONPATH=/opt/tvm/python \
    TVM_LIBRARY_PATH=/opt/tvm/lib

RUN pip3 install --no-cache-dir --break-system-packages \
        apache-tvm-ffi==${TVM_FFI_VERSION} tflite onnx ml_dtypes numpy typing_extensions \
        digitalhub \
    && python3 -c "import tvm; print('tvm', tvm.__version__); import onnx, tflite, digitalhub; from tvm.relax.frontend.tflite import from_tflite; print('onnx+tflite+sdk ok')"
