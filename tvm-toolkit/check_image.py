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
backends = provenance.get("compiled_backends", ["cpu"])
assert backends in (["cpu"], ["cpu", "cuda"]), backends
required_libraries = {
    "libtvm_runtime.so", "libtvm_runtime_extra.so", "libtvm_ffi.so", "libtvm_compiler.so",
}
if "cuda" in backends:
    required_libraries.add("libtvm_runtime_cuda.so")
    cuda = provenance["cuda_build"]
    assert cuda["tvm_git_commit"] == provenance["tvm_git_commit"]
    assert cuda["tvm_ffi_git_commit"] == provenance["tvm_ffi_git_commit"]
    assert cuda["library_sha256"] == provenance["libraries"]["libtvm_runtime_cuda.so"]
    assert cuda["build_target"] == "tvm_runtime_cuda"
    assert cuda["cuda_version"] == os.environ["TVM_CUDA_VERSION"]
    cache = Path("/opt/tvm/cuda-CMakeCache.txt")
    assert hashlib.sha256(cache.read_bytes()).hexdigest() == cuda["cmake_cache_sha256"]
    cmake_options = {}
    for line in cache.read_text().splitlines():
        if line and not line.startswith(("#", "//")) and ":" in line and "=" in line:
            name, _, value = line.partition("=")
            cmake_options[name.partition(":")[0]] = value
    assert cmake_options["USE_CUDA"] == "/usr/local/cuda"
    loader_paths = os.environ["LD_LIBRARY_PATH"].split(":")
    assert {"/usr/local/nvidia/lib", "/usr/local/nvidia/lib64", "/opt/tvm/lib",
            "/usr/local/cuda/lib64"} <= set(loader_paths), loader_paths
    assert not any("stubs" in path for path in loader_paths), loader_paths
    assert os.environ["NVIDIA_DRIVER_CAPABILITIES"] == "compute,utility"
assert set(provenance["libraries"]) == required_libraries, provenance["libraries"]
assert {path.name for path in Path("/opt/tvm/lib").glob("*.so")} == required_libraries
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
import onnx_ir
import onnxsim
import psutil
import tflite
import xgboost
import requests
from tvm.relax.frontend.tflite import from_tflite

from onnx import TensorProto, helper
from onnx_ir.passes.common import TopologicalSortPass

onnx_probe = helper.make_model(
    helper.make_graph(
        [helper.make_node("Identity", ["x"], ["y"])],
        "simplifier_probe",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [1, 4])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [1, 4])],
    ),
    opset_imports=[helper.make_opsetid("", 17)],
)
simplified_probe, valid = onnxsim.simplify(onnx_probe)
onnx.checker.check_model(onnx_ir.to_proto(TopologicalSortPass()(onnx_ir.from_proto(onnx_probe)).model))
assert valid and simplified_probe.ir_version == onnx.IR_VERSION
print("ONNX simplification ok: IR", onnx_probe.ir_version)

assert tvm.get_global_func("tvm.contrib.random.random_fill_for_measure", allow_missing=True)
assert md.packages_distributions().get("digitalhub") is None
print("onnx+onnxsim+tflite+metaschedule+http ok; no DigitalHub SDK")

from tvm import relax, tirx
from tvm.support import cc

probe = tirx.PrimFunc([], tirx.Evaluate(0)).with_attr("global_symbol", "toolchain_probe")
identity = relax.BlockBuilder()
x = relax.Var("x", relax.TensorType((4,), "float32"))
with identity.function("main", [x]):
    identity.emit_func_output(x)
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
        # A bytecode VM without TIR kernels exports a C stub and needs TVM headers.
        executable = relax.build(identity.get(), target=tvm.target.Target(target), exec_mode="bytecode")
        executable.export_library(
            str(Path(folder) / "identity.so"),
            fcompile=cc.cross_compiler(compiler, get_target_triple=lambda: triple),
        )
    print("toolchain ok:", triple, compiler)
    print("bytecode identity export ok:", triple)
