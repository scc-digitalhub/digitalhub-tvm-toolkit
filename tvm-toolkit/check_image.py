# SPDX-FileCopyrightText: © 2025 DSLab - Fondazione Bruno Kessler
#
# SPDX-License-Identifier: Apache-2.0

import hashlib
import importlib.metadata as md
import json
import os
import shutil
import tempfile
from pathlib import Path

import tvm

provenance = json.loads(Path("/opt/tvm/provenance.json").read_text())
assert tvm.__version__ == os.environ["TVM_VERSION"]
assert md.version("apache-tvm-ffi") == os.environ["TVM_FFI_VERSION"]
assert provenance["tvm_git_commit"] == os.environ["TVM_GIT_COMMIT"]
assert provenance["tvm_ffi_git_commit"] == os.environ["TVM_FFI_GIT_COMMIT"]
for library in Path("/opt/tvm/lib").glob("*.so"):
    assert hashlib.sha256(library.read_bytes()).hexdigest() == provenance["libraries"][library.name], library.name

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
import requests
from tvm.relax.frontend.tflite import from_tflite

assert tvm.get_global_func("tvm.contrib.random.random_fill_for_measure", allow_missing=True)
assert md.packages_distributions().get("digitalhub") is None
print("onnx+onnxsim+tflite+metaschedule+http ok; no DigitalHub SDK")

from tvm import tirx

probe = tirx.PrimFunc([], tirx.Evaluate(0)).with_attr("global_symbol", "toolchain_probe")
for triple, compiler in (
    ("x86_64-linux-gnu", "x86_64-linux-gnu-g++"),
    ("aarch64-linux-gnu", "aarch64-linux-gnu-g++"),
    ("armv7l-unknown-linux-gnueabihf", "arm-linux-gnueabihf-g++"),
):
    assert shutil.which(compiler), compiler
    target = {"kind": "llvm", "mtriple": triple}
    if triple.startswith("armv7"):
        target.update({"mfloat-abi": "hard", "mattr": ["+neon"]})
    module = tvm.tirx.build(tvm.IRModule({"toolchain_probe": probe}), target=tvm.target.Target(target))
    with tempfile.TemporaryDirectory() as folder:
        module.export_library(str(Path(folder) / "probe.so"), cc=compiler)
    print("toolchain ok:", triple, compiler)
