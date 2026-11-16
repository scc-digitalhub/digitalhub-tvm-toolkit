# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

"""Extend the inherited CPU provenance with a checked, separately built backend."""

import datetime
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path('/opt/tvm')
path = root / 'provenance.json'
manifest = json.loads(path.read_text())
cuda = json.loads((root / 'cuda-build-provenance.json').read_text())
for key in ('tvm_git_commit', 'tvm_ffi_git_commit'):
    assert cuda[key] == manifest[key] == os.environ[key.upper()], key
cache_path = root / 'cuda-CMakeCache.txt'
assert hashlib.sha256(cache_path.read_bytes()).hexdigest() == cuda['cmake_cache_sha256']
cache = {}
for line in cache_path.read_text().splitlines():
    if line and not line.startswith(('#', '//')) and ':' in line and '=' in line:
        name, _, value = line.partition('=')
        cache[name.partition(':')[0]] = value
assert cache['USE_CUDA'] == '/usr/local/cuda', cache.get('USE_CUDA')
assert cache['CMAKE_CUDA_ARCHITECTURES'] == '87'
assert cache['CMAKE_BUILD_WITH_INSTALL_RPATH'] == 'ON'
library = root / 'lib/libtvm_runtime_cuda.so'
assert hashlib.sha256(library.read_bytes()).hexdigest() == cuda['library_sha256']
manifest['compiled_backends'] = ['cpu', 'cuda']
manifest['libraries'][library.name] = cuda['library_sha256']
manifest['cuda_build'] = cuda
manifest['cuda_toolkit'] = {
    'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_repository': 'scc-digitalhub/digitalhub-tvm-toolkit',
    'source_git_commit': os.environ['TVM_TOOLKIT_CUDA_SOURCE_REVISION'],
    'base_image': os.environ['TVM_TOOLKIT_BASE_IMAGE'],
}
manifest['cuda_packages'] = subprocess.check_output(
    ['dpkg-query', '-W', '-f=${Package}=${Version}\n', 'cuda-*', 'libnvvm-*', 'libnvptxcompiler-*'],
    text=True,
).splitlines()
path.write_text(json.dumps(manifest, indent=2) + '\n')
