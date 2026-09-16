# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

# Packages a TVM build (lib/*.so + python/tvm) staged by the GitHub workflow
# .github/workflows/tvm-toolkit-image.yml, which passes the versions and commits as
# build args. ubuntu:24.04 matches the glibc/libstdc++ of the build runners.
FROM ubuntu:24.04

# Version-coupled deps: LLVM_VERSION = matching libLLVM major (TVM codegen),
# TVM_FFI_VERSION = apache-tvm-ffi bundled in this TVM.
ARG LLVM_VERSION=18
ARG TVM_VERSION=0.26.0
ARG TVM_FFI_VERSION=0.1.13.post2
ARG TVM_GIT_COMMIT=unknown
ARG TVM_FFI_GIT_COMMIT=unknown
LABEL org.opencontainers.image.version="${TVM_VERSION}" \
    org.opencontainers.image.source="https://github.com/apache/tvm" \
    org.opencontainers.image.revision="${TVM_GIT_COMMIT}" \
    org.digitalhub.tvm-ffi.version="${TVM_FFI_VERSION}" \
    org.digitalhub.tvm-ffi.revision="${TVM_FFI_GIT_COMMIT}"

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
COPY provenance.json /opt/tvm/provenance.json

ENV LD_LIBRARY_PATH=/opt/tvm/lib \
    PYTHONPATH=/opt/tvm/python \
    TVM_LIBRARY_PATH=/opt/tvm/lib \
    TVM_VERSION=${TVM_VERSION} \
    TVM_GIT_COMMIT=${TVM_GIT_COMMIT} \
    TVM_FFI_VERSION=${TVM_FFI_VERSION} \
    TVM_FFI_GIT_COMMIT=${TVM_FFI_GIT_COMMIT}

# Python side: the frontends (onnx, onnxsim, tflite), what MetaSchedule tuning needs
# (xgboost cost model, cloudpickle and psutil for the builder workers, scipy) and the
# digitalhub SDK that publishes the Models. The tvm-ffi wheel is then rewired to the
# libtvm_ffi.so of this TVM build, and every import is checked before the image is done.
RUN pip3 install --no-cache-dir --break-system-packages \
        apache-tvm-ffi==${TVM_FFI_VERSION} tflite onnx onnxsim==0.7.3 ml_dtypes numpy typing_extensions \
        cloudpickle psutil scipy xgboost-cpu \
        digitalhub \
    && FFI_LIB="$(python3 -c 'import importlib.util, pathlib; print(pathlib.Path(importlib.util.find_spec("tvm_ffi").origin).parent / "lib/libtvm_ffi.so")')" \
    && test -f "${FFI_LIB}" \
    && rm "${FFI_LIB}" \
    && ln -s /opt/tvm/lib/libtvm_ffi.so "${FFI_LIB}" \
    && python3 -c "import importlib.metadata as md, json, os, pathlib, tvm; provenance=json.loads(pathlib.Path('/opt/tvm/provenance.json').read_text()); assert tvm.__version__ == os.environ['TVM_VERSION']; assert md.version('apache-tvm-ffi') == os.environ['TVM_FFI_VERSION']; assert provenance['tvm_git_commit'] == os.environ['TVM_GIT_COMMIT']; assert provenance['tvm_ffi_git_commit'] == os.environ['TVM_FFI_GIT_COMMIT']; loaded={line.split()[-1] for line in open('/proc/self/maps') if line.split()[-1].endswith('/libtvm_ffi.so')}; assert loaded == {'/opt/tvm/lib/libtvm_ffi.so'}, loaded; print('tvm', tvm.__version__, 'ffi', md.version('apache-tvm-ffi'), 'provenance ok'); import cloudpickle, onnx, onnxsim, psutil, tflite, xgboost, digitalhub; from tvm.relax.frontend.tflite import from_tflite; from tvm.backend import _autoload_backends; assert tvm.get_global_func('tvm.contrib.random.random_fill_for_measure', allow_missing=True); print('onnx+onnxsim+tflite+metaschedule+sdk ok')"
