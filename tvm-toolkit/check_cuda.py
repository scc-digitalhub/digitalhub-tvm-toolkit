# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

"""Compile and serialize CUDA kernels without allocating or executing on a GPU."""

import argparse
import ctypes
import hashlib
import json
import os
import platform
import shutil
import struct
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--require-no-gpu', action='store_true')
args = parser.parse_args()
if args.require_no_gpu:
    assert not list(Path('/dev').glob('nvidia*')), 'NVIDIA device mounted in offline check'
assert os.environ.get('TVM_CUDA_COMPILE_MODE') == 'nvcc'
assert os.environ.get('TVM_CUDA_NVCC_NO_FAST_MATH') == '1'
assert not os.environ.get('TVM_COMPILE_FORCE_FALLBACK'), 'raw CUDA fallback is not supported'
assert shutil.which('nvcc')

import tvm
from tvm.script import tirx as T

root = Path('/opt/tvm')
manifest = json.loads((root / 'provenance.json').read_text())
assert manifest['compiled_backends'] == ['cpu', 'cuda']
sidecar = root / 'lib/libtvm_runtime_cuda.so'
assert hashlib.sha256(sidecar.read_bytes()).hexdigest() == manifest['libraries'][sidecar.name]
ctypes.CDLL(str(sidecar), mode=os.RTLD_NOW | os.RTLD_LOCAL)
for name in ('ffi.Module.create.cuda', 'ffi.Module.load_from_bytes.cuda'):
    assert tvm.get_global_func(name, allow_missing=True), f'CUDA runtime factory missing: {name}'
loaded = {
    line.split()[-1]
    for line in Path('/proc/self/maps').read_text().splitlines()
    if line.split()[-1].endswith('/libtvm_runtime_cuda.so')
}
assert loaded == {str(sidecar)}, loaded


@T.prim_func(s_tir=True)
def cuda_add(A: T.Buffer((32,), 'float32'), B: T.Buffer((32,), 'float32'),
             C: T.Buffer((32,), 'float32')):
    T.func_attr({'global_symbol': 'cuda_add', 'tirx.noalias': True})
    for bx in T.thread_binding(1, thread='blockIdx.x'):
        for tx in T.thread_binding(32, thread='threadIdx.x'):
            C[tx] = A[tx] + B[tx]


@T.prim_func(s_tir=True)
def cuda_matmul(A: T.Buffer((16, 16), 'float32'), B: T.Buffer((16, 16), 'float32'),
                C: T.Buffer((16, 16), 'float32')):
    T.func_attr({'global_symbol': 'cuda_matmul', 'tirx.noalias': True})
    for bx in T.thread_binding(1, thread='blockIdx.x'):
        for tx in T.thread_binding(256, thread='threadIdx.x'):
            C[tx // 16, tx % 16] = T.float32(0)
            for k in range(16):
                C[tx // 16, tx % 16] = C[tx // 16, tx % 16] + A[tx // 16, k] * B[k, tx % 16]


def cuda_modules(module):
    found = []
    if module.kind == 'cuda':
        assert module.is_runnable(), 'raw CUDA source fallback is not a compiled CUDA module'
        found.append(module)
    for child in module.imports:
        found.extend(cuda_modules(child))
    return found


native_machine = {'x86_64': 62, 'aarch64': 183}[platform.machine()]
for triple, compiler, machine in (
    ('x86_64-linux-gnu', 'x86_64-linux-gnu-g++', 62),
    ('aarch64-linux-gnu', 'aarch64-linux-gnu-g++', 183),
):
    target = tvm.target.Target(
        {'kind': 'cuda', 'arch': 'sm_87'},
        host={'kind': 'llvm', 'mtriple': triple},
    )
    for name, function in (('add', cuda_add), ('matmul', cuda_matmul)):
        # The upstream nvcc callback reads Target.current for its architecture.
        with target:
            module = tvm.tirx.build(tvm.IRModule({'main': function}), target=target)
        assert cuda_modules(module), 'no CUDA modules in compiled result'
        with tempfile.TemporaryDirectory() as folder:
            library = Path(folder) / (name + '.so')
            module.export_library(str(library), cc=compiler)
            data = library.read_bytes()
            assert data[:4] == b'\x7fELF'
            assert struct.unpack_from('<H', data, 18)[0] == machine, triple
            # A serialized native model loads through the standard runtime with
            # only compiled CUDA data: no Python callback or nvcc at load time.
            if machine == native_machine:
                saved_nvcc = os.environ['PATH']
                os.environ['PATH'] = '/nonexistent'
                try:
                    restored = tvm.runtime.load_module(str(library))
                    assert cuda_modules(restored)
                    assert all(not child.inspect_source('cuda') for child in cuda_modules(restored))
                finally:
                    os.environ['PATH'] = saved_nvcc
        print('offline CUDA compilation/export ok:', name, 'sm_87', triple)
print('CUDA factory and native serialization verified; GPU execution was not tested')
