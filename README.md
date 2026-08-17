# digitalhub-tvm-toolkit

Builds the **`tvm-toolkit`** Docker image — the single image DigitalHub CORE runs for
the TVM `tvm+build` and `tvm+compile` tasks.

```
tvm-toolkit  =  Apache TVM (python + libs) + LLVM + native g++ + ARM cross-toolchain
                + onnx + tflite + digitalhub SDK
                 · tvm+build     onnx | tflite  →  Relax IR   (Model tvm-ir)
                 · tvm+compile   Relax IR       →  model.so   (Model tvm-so)
```

ONNX and TFLite are the supported source formats, quantized ones included. One image
covers both for every LLVM target (x86_64 + cross-compile aarch64/armv7l). It packages a
**host build of TVM** (the `.so` + `python/tvm`) — it does not compile TVM in-image.

Quantization is an axis of its own, independent of the format: a TFLite full-integer
export and a QDQ ONNX both reach the builders as int8, and both have their affine
params (`scale`, `zero_point`) carried into `metadata.json`.

> Serving is a separate concern in its own projects: **`digitalhub-tvm-rust`** (rust
> `tvm-serve` image) and **`digitalhub-serverless`** (native Go runtime image). This
> project builds only the build/compile toolkit.

## What produces what

| file | role |
|---|---|
| `build-tvm.sh` | compile Apache TVM from source (cmake+ninja). **Prerequisite**, ~20–60 min, idempotent. |
| `build-image.sh` | package the host TVM build into the `tvm-toolkit` image, applying every patch in `patches/`. |
| `patches/*.patch` | fixes carried on top of the packaged TVM. **They must apply**: the build aborts otherwise, because an unpatched image builds fine and only fails at run time. |
| `_tvm-version.sh` | auto-resolve the TVM version + coupled deps (`TVM_FFI_VERSION`, `LLVM_VERSION`) and the image tag (`major.minor`). |
| `tvm-toolkit/Dockerfile` | the image definition (ubuntu:24.04 + LLVM + g++ + cross-toolchain + onnx + tflite + SDK). |

## Build

```bash
./build-tvm.sh                 # 1) compile TVM (once). TVM_VERSION=0.25.0 for a specific one
./build-image.sh --load        # 2) build tvm-toolkit:<tag> and load it into minikube
./build-image.sh --push        #    ... or push: REGISTRY=<host[/org]> prefixes the ref; empty pushes the bare $TAG
```

The image tag is `tvm-toolkit:<major.minor>` (e.g. `tvm-toolkit:0.25`), derived from the
resolved TVM version. `build-image.sh` fails fast if TVM is not compiled yet.

**Version resolution** (`_tvm-version.sh`): explicit `TVM_VERSION` → else the highest
locally-**built** TVM under `$TVM_ROOT` (default `~/tvm/src`). Override `TVM_VERSION`,
`TVM_FFI_VERSION`, `LLVM_VERSION`, `TVM_ROOT` via env.

## Use from CORE

Point the runtime-tvm image overrides at the built tag (env vars in digitalhub-core):

```
RUNTIME_TVM_BUILDER_ONNX     → tvm+build image, onnx sources    (tvm-toolkit)
RUNTIME_TVM_BUILDER_TFLITE   → tvm+build image, tflite sources  (tvm-toolkit)
RUNTIME_TVM_COMPILER         → tvm+compile image                (tvm-toolkit)
# e.g. 192.168.49.1:5000/tvm-toolkit:0.25  (registry ref reachable from inside the cluster)
```

The pod scripts (`entrypoint.sh`, `builder_*.py`, `compiler.py`, `_dh_publish.py`) are NOT
baked in — CORE injects them at runtime as ContextSources. This image is only the toolchain.

## Gotcha

- **`tvm+compile` OOMKills (exit 137)** with default resources (~282 MB): linking `model.so`
  needs more. On the compile run set `resources` mem=`8Gi`, cpu=`4`.

CPU targets, cross-compiled via LLVM (x86_64 / aarch64). Validated E2E on
TVM 0.24.0 and 0.25.0 (yolov8: `images` FP32 `[1,3,640,640]` → `output0` `[1,84,8400]`).
