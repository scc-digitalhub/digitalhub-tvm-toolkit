#!/usr/bin/env bash
# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

# The minimal CUDA 13.2.1 compiler/runtime set; no driver installation.
set -euo pipefail
case "$(dpkg --print-architecture)" in
    amd64) cuda_repo_arch=x86_64 ;;
    arm64) cuda_repo_arch=sbsa ;;
    *) echo "CUDA toolkit requires AMD64 or ARM64" >&2; exit 1 ;;
esac
python3 - "$cuda_repo_arch" <<'PY'
import sys
import urllib.request

url = ("https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/"
       + sys.argv[1] + "/cuda-keyring_1.1-1_all.deb")
urllib.request.urlretrieve(url, "/tmp/cuda-keyring.deb")
PY
dpkg -i /tmp/cuda-keyring.deb
apt-get update
# Component versions from NVIDIA's 13.2.1 image definitions. Pin dependencies
# too: the 13-2 repository also contains newer CUDA 13.2 update releases.
apt-get install -y --no-install-recommends \
    cuda-toolkit-config-common=13.2.75-1 \
    cuda-toolkit-13-config-common=13.2.75-1 \
    cuda-toolkit-13-2-config-common=13.2.75-1 \
    cuda-nvcc-13-2=13.2.78-1 \
    cuda-crt-13-2=13.2.78-1 \
    cuda-cudart-13-2=13.2.75-1 \
    cuda-cudart-dev-13-2=13.2.75-1 \
    cuda-driver-dev-13-2=13.2.75-1 \
    cuda-cccl-13-2=13.2.75-1 \
    cuda-culibos-dev-13-2=13.2.75-1 \
    libnvvm-13-2=13.2.78-1 \
    libnvptxcompiler-13-2=13.2.78-1
rm -rf /var/lib/apt/lists/* /tmp/cuda-keyring.deb

# The toolkit supplies libcuda.so, but dlopen needs its SONAME libcuda.so.1.
# Isolate that alias. Only an explicit LD_LIBRARY_PATH opts in to this stub.
mkdir -p /opt/tvm/cuda-driver-stubs
cp -L /usr/local/cuda/lib64/stubs/libcuda.so /opt/tvm/cuda-driver-stubs/libcuda.so.1
