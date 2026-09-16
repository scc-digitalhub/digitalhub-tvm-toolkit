# digitalhub-tvm-toolkit

The **`ghcr.io/scc-digitalhub/tvm-toolkit`** image: the toolchain that DigitalHub CORE
(`runtime-tvm`) runs for the **`tvm+build`** and **`tvm+compile`** tasks.

```
tvm+build     onnx | tflite  ──►  Relax IR   (Model tvm-ir)
tvm+compile   Relax IR       ──►  model.so   (Model tvm-so), optionally tuned
```

The image holds only the tools. The scripts that do the work (`entrypoint.sh`,
`builder_onnx.py`, `builder_tflite.py`, `compiler.py`, `_dh_publish.py`) live in
`runtime-tvm`, and CORE injects them into each Job. Serving uses other images:
`tvm-runtime-go` (`digitalhub-serverless`) and `tvm-runtime-rust` (`digitalhub-tvm-rust`).

## What is inside

| Component      | Details                                                                                |
| -------------- | -------------------------------------------------------------------------------------- |
| Apache TVM     | Compiler and runtime libraries in `/opt/tvm/lib`, Python package in `/opt/tvm/python`. |
| apache-tvm-ffi | Python wheel linked to the `libtvm_ffi.so` of the same TVM build.                      |
| LLVM           | `libllvm18`, used by TVM to generate code.                                             |
| C++ compilers  | Native `g++`, `aarch64-linux-gnu-g++` (arm64) and `arm-linux-gnueabihf-g++` (armv7l).  |
| Model formats  | `onnx`, `onnxsim`, `tflite`.                                                           |
| Tuning         | What MetaSchedule needs: `xgboost`, `cloudpickle`, `psutil`, `scipy`.                  |
| DigitalHub SDK | `digitalhub`, to upload the results as Models.                                         |
| Build record   | `/opt/tvm/provenance.json`: versions, commits and SHA-256 of the libraries.            |

Base image `ubuntu:24.04`, published for `linux/amd64` and `linux/arm64`. Both can compile
for every `tvm+compile` target (x86, arm64, armv7l).

### Environment variables

| Variable                                | Value                                       |
| --------------------------------------- | ------------------------------------------- |
| `TVM_VERSION`, `TVM_GIT_COMMIT`         | Apache TVM release and commit in the image. |
| `TVM_FFI_VERSION`, `TVM_FFI_GIT_COMMIT` | apache-tvm-ffi release and commit.          |
| `PYTHONPATH`                            | `/opt/tvm/python`                           |
| `LD_LIBRARY_PATH`, `TVM_LIBRARY_PATH`   | `/opt/tvm/lib`                              |

`compiler.py` copies `TVM_VERSION` and `TVM_GIT_COMMIT` into the `metadata.json` of every
compiled model, and the serve images refuse models whose values differ from their own.

## Versions and tags

**The image tag is the git tag, and it is the Apache TVM version**: tag `0.26.0` builds
`tvm-toolkit:0.26.0` on Apache TVM `0.26.0`.

| TVM      | apache-tvm-ffi | LLVM |
| -------- | -------------- | ---- |
| `0.24.x` | `0.1.11`       | 18   |
| `0.25.x` | `0.1.12`       | 18   |
| `0.26.x` | `0.1.13.post2` | 18   |

A new TVM version needs its apache-tvm-ffi release added to the workflow. Next to the
multi-architecture tag, each architecture also gets its own tag (`<tag>-amd64`,
`<tag>-arm64`).

## Release

Push a tag `X.Y.Z` (or `X.Y`) and GitHub Actions (`.github/workflows/tvm-toolkit-image.yml`)
does the rest. For each architecture, on a native runner, it:

1. compiles Apache TVM `vX.Y.Z` with LLVM;
2. copies the libraries and `python/tvm`, and applies every patch in `patches/`;
3. writes `provenance.json` and builds the image, which links the apache-tvm-ffi wheel to
   the TVM build and checks every import;
4. pushes `<tag>-<arch>`.

A last job joins the images into the multi-architecture tag. To rebuild a release, run the
workflow by hand on its tag.

### Build arguments

The workflow passes them to `tvm-toolkit/Dockerfile`. The build context must contain
`lib/`, `python/` and `provenance.json`.

| Argument             | Default        | Description                                 |
| -------------------- | -------------- | ------------------------------------------- |
| `TVM_VERSION`        | `0.26.0`       | Apache TVM release in `lib/` and `python/`. |
| `TVM_GIT_COMMIT`     | `unknown`      | Commit of that release.                     |
| `TVM_FFI_VERSION`    | `0.1.13.post2` | apache-tvm-ffi wheel to install.            |
| `TVM_FFI_GIT_COMMIT` | `unknown`      | Commit of tvm-ffi.                          |
| `LLVM_VERSION`       | `18`           | LLVM library to install.                    |

## Patches

The files in `patches/` are applied to the TVM Python package. **They must apply**: the
build stops otherwise, because an image without them builds fine and fails only at run
time.

| Patch                        | Why                                                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `tflite-quantized-ops.patch` | Lets the TFLite importer convert full-integer quantized models: enables six operators it already supports and fixes scalar quantized constants. |

## Use from CORE

`runtime-tvm` uses the published tag by default. To try another image, set on CORE:

| Variable                     | Used by                    |
| ---------------------------- | -------------------------- |
| `RUNTIME_TVM_BUILDER_ONNX`   | `tvm+build`, ONNX models   |
| `RUNTIME_TVM_BUILDER_TFLITE` | `tvm+build`, TFLite models |
| `RUNTIME_TVM_COMPILER`       | `tvm+compile`              |

A single run can also set `image` in its task.

Tips:

- **Memory.** Compiling needs more than the default resources: give `tvm+compile` at
  least `mem: 8Gi` and `cpu: 4`, or the Job is killed (exit code 137).
- **Speed.** Untuned CPU code is slow. The `runtime-tvm` README explains tuning and lists
  all the task options.

## Related projects

| Project                                    | Role                                    |
| ------------------------------------------ | --------------------------------------- |
| `digitalhub-core` (`runtimes/runtime-tvm`) | Runs the tasks and injects the scripts. |
| `digitalhub-serverless` (`tvm-runtime-go`) | Default serve image.                    |
| `digitalhub-tvm-rust` (`tvm-runtime-rust`) | Alternative serve image.                |

The images of one release must share the same TVM version and commit.
