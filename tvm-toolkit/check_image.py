# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

import importlib.metadata as md
import json
import os
from pathlib import Path

import tvm

provenance = json.loads(Path("/opt/tvm/provenance.json").read_text())
assert tvm.__version__ == os.environ["TVM_VERSION"]
assert md.version("apache-tvm-ffi") == os.environ["TVM_FFI_VERSION"]
assert provenance["tvm_git_commit"] == os.environ["TVM_GIT_COMMIT"]
assert provenance["tvm_ffi_git_commit"] == os.environ["TVM_FFI_GIT_COMMIT"]

loaded = {
    line.split()[-1]
    for line in Path("/proc/self/maps").read_text().splitlines()
    if line.split()[-1].endswith("/libtvm_ffi.so")
}
assert loaded == {"/opt/tvm/lib/libtvm_ffi.so"}, loaded
print("tvm", tvm.__version__, "ffi", md.version("apache-tvm-ffi"), "provenance ok")

import cloudpickle
import onnx
import onnxsim
import psutil
import tflite
import xgboost
import digitalhub
from tvm.relax.frontend.tflite import from_tflite
from tvm.backend import _autoload_backends

assert tvm.get_global_func("tvm.contrib.random.random_fill_for_measure", allow_missing=True)
print("onnx+onnxsim+tflite+metaschedule+sdk ok")
