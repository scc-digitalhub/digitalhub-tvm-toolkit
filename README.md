# digitalhub-tvm-toolkit

Builds the **`tvm-toolkit`** Docker image — the single image DigitalHub CORE runs for
the TVM `tvm+build` and `tvm+compile` tasks.

```
tvm-toolkit  =  Apache TVM (python + libs) + LLVM + native g++ + ARM cross-toolchain
                + onnx + tflite + MetaSchedule tuning deps + digitalhub SDK
                 · tvm+build     onnx | tflite  →  Relax IR   (Model tvm-ir)
                 · tvm+compile   Relax IR       →  model.so   (Model tvm-so)
```

ONNX and TFLite are the supported source formats, quantized ones included. One image
covers both for every LLVM target (x86_64 + cross-compile aarch64/armv7l), and it is
published for `linux/amd64` and `linux/arm64`.

Quantization is an axis of its own, independent of the format: a TFLite full-integer
export and a QDQ ONNX both reach the builders as int8, and both have their affine
params (`scale`, `zero_point`) carried into `metadata.json`.

> Serving is a separate concern in its own projects: **`digitalhub-serverless`** (native
> Go runtime image, CORE's default) and **`digitalhub-tvm-rust`** (Rust `tvm-serve`
> image). This project builds only the build/compile toolkit.

## What is in the repository

| file                                     | role                                                                                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/tvm-toolkit-image.yml` | builds and publishes the image when a tag is pushed (see below).                                                                                             |
| `tvm-toolkit/Dockerfile`                 | the image definition (ubuntu:24.04 + LLVM + g++ + cross-toolchain + onnx + tflite + tuning deps + SDK).                                                       |
| `patches/*.patch`                        | fixes carried on top of the packaged TVM. **They must apply**: the build aborts otherwise, because an unpatched image builds fine and only fails at run time. |

## Build

The image is built by GitHub Actions when a tag is pushed. **The image tag is the git
tag**, and it names the Apache TVM release: pushing `0.26.0` publishes
`ghcr.io/scc-digitalhub/tvm-toolkit:0.26.0` built on TVM `0.26.0` (the matching
`apache-tvm-ffi` wheel and LLVM major are resolved by the workflow).

For each architecture, on a native runner, the workflow compiles Apache TVM with LLVM,
applies every patch in `patches/`, stages the libraries, `python/tvm` and a provenance
manifest, and builds the image. The Dockerfile then rewires the `apache-tvm-ffi` wheel
to the `libtvm_ffi.so` of that same build and checks every import. A last job joins
the two images into one multi-architecture tag.

## Use from CORE

The runtime-tvm defaults point at the published tag. To try another build, override the
images with env vars in digitalhub-core:

```
RUNTIME_TVM_BUILDER_ONNX     → tvm+build image, onnx sources    (tvm-toolkit)
RUNTIME_TVM_BUILDER_TFLITE   → tvm+build image, tflite sources  (tvm-toolkit)
RUNTIME_TVM_COMPILER         → tvm+compile image                (tvm-toolkit)
# e.g. 192.168.49.1:5000/tvm-toolkit:0.26.0  (registry ref reachable from inside the cluster)
```

The pod scripts (`entrypoint.sh`, `builder_*.py`, `compiler.py`, `_dh_publish.py`) are NOT
baked in — CORE injects them at runtime as ContextSources. This image is only the toolchain.

## Compiling for speed

On CPU, TVM has no default schedule for the operators: without tuning they are compiled
as plain loops, often many times slower than ONNX Runtime. `tvm+compile` can tune them
with **MetaSchedule**, which this image fully supports:

- `tuning_mode: tune` measures candidate schedules on the compile Job and keeps the best
  ones in a database published with the model (`tuning/`);
- `tuning_mode: apply` reuses such a database for the same IR and target, without
  measuring again;
- on LLVM targets the weights are also **prepacked** into the layout the tuned schedules
  prefer (TVM's `cpu_weight_prepack`);
- every compile times a few inferences of the finished `model.so` (`benchmark_runs`) and
  records them in `metadata.json`, so builds can be compared.

Give the tuning enough trials: at least `tasks × min(64, max_trials_per_task)` to measure
every task once. See the runtime-tvm README in digitalhub-core for all the options.

## Gotcha

- **`tvm+compile` OOMKills (exit 137)** with default resources (~282 MB): linking `model.so`
  needs more. On the compile run set `resources` mem=`8Gi`, cpu=`4`.

CPU targets, cross-compiled via LLVM (x86_64 / aarch64 / armv7l). Validated E2E on
TVM 0.26.0 (yolov8: `images` FP32 `[1,3,640,640]` → `output0` `[1,84,8400]`).
