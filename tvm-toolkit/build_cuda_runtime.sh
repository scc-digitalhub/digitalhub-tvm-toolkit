#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
tvm_commit=c7b458e946bc4266915da582457476bdcd9705ae
ffi_commit=12dbf053b3d9ba4ebd9da3123b1aeca79cf74229
test "$TVM_VERSION" = 0.26.0
test "$TVM_GIT_COMMIT" = "$tvm_commit"
test "$TVM_FFI_VERSION" = 0.1.13.post2
test "$TVM_FFI_GIT_COMMIT" = "$ffi_commit"
git clone --depth 1 --branch v0.26.0 --recurse-submodules --shallow-submodules \
    https://github.com/apache/tvm /src/tvm
test "$(git -C /src/tvm rev-parse HEAD)" = "$tvm_commit"
test "$(git -C /src/tvm/3rdparty/tvm-ffi rev-parse HEAD)" = "$ffi_commit"
# Explicit architecture avoids CMake's default 'native', which requires a GPU.
# No contrib BLAS/cuDNN/NVRTC dependency is needed for the initial nvcc baseline.
cmake -S /src/tvm -B /src/build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DCMAKE_CUDA_ARCHITECTURES=87 \
    -DUSE_CUDA=/usr/local/cuda \
    -DCUDA_CUDA_LIBRARY=/usr/local/cuda/lib64/stubs/libcuda.so \
    -DUSE_LLVM=OFF -DUSE_GTEST=OFF -DUSE_CCACHE=OFF
cmake --build /src/build --target tvm_runtime_cuda --parallel "${TVM_CUDA_BUILD_JOBS:-2}"
mkdir -p /stage
cp /src/build/lib/libtvm_runtime_cuda.so /stage/
strip --strip-debug /stage/libtvm_runtime_cuda.so
# Check linkage against the shipped CPU runtime/FFI, without using the freshly
# built dependency libraries. RTLD_NOW in check_cuda.py additionally resolves
# every symbol when the plugin registers in the final image.
readelf -d /stage/libtvm_runtime_cuda.so > /stage/dynamic.txt
if grep -E '(RPATH|RUNPATH).*stubs' /stage/dynamic.txt; then
    echo "CUDA runtime must not embed the driver stub search path" >&2
    exit 1
fi
LD_LIBRARY_PATH=/opt/tvm/cuda-driver-stubs:/opt/tvm/lib:/usr/local/cuda/lib64 \
    ldd -r /stage/libtvm_runtime_cuda.so > /stage/ldd.txt
if grep -E 'not found|undefined symbol' /stage/ldd.txt; then
    echo "CUDA runtime does not resolve against the inherited CPU libraries" >&2
    exit 1
fi
cp /src/build/CMakeCache.txt /stage/cuda-CMakeCache.txt
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

cache = Path('/stage/cuda-CMakeCache.txt')
manifest = {
    "tvm_git_commit": os.environ['TVM_GIT_COMMIT'],
    "tvm_ffi_git_commit": os.environ['TVM_FFI_GIT_COMMIT'],
    "cmake_cache_sha256": hashlib.sha256(cache.read_bytes()).hexdigest(),
    "library_sha256": hashlib.sha256(Path('/stage/libtvm_runtime_cuda.so').read_bytes()).hexdigest(),
    "build_target": "tvm_runtime_cuda",
    "cuda_version": os.environ['TVM_CUDA_VERSION'],
    "linkage": Path('/stage/ldd.txt').read_text(),
}
Path('/stage/cuda-build-provenance.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
