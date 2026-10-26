# DigitalHub TVM Toolkit

The image **`ghcr.io/scc-digitalhub/tvm-toolkit`** contains [Apache TVM](https://tvm.apache.org/)
and the tools around it. DigitalHub CORE (`runtime-tvm`) uses it for build and compile Runs:

```
tvm+build     ONNX or TFLite model  ──►  Relax IR   (Model tvm-ir)
tvm+compile   Relax IR              ──►  model.so   (Model tvm-so), optionally tuned
```

The image holds only the tools. The scripts that do the work are part of `runtime-tvm`:
CORE mounts them into each Job, so a new CORE version updates them without a new image.
The compiled models are served by **DigitalHub TVM Runtime Go** and **DigitalHub TVM
Runtime Rust**.

## What is inside

| Component      | Details                                                                                |
| -------------- | -------------------------------------------------------------------------------------- |
| Apache TVM     | Compiler and runtime libraries in `/opt/tvm/lib`, Python package in `/opt/tvm/python`. |
| apache-tvm-ffi | Python wheel linked to the `libtvm_ffi.so` of the same TVM build.                      |
| LLVM           | `libllvm18`, used by TVM to generate the code.                                         |
| C++ compilers  | Native `g++`, `x86_64-linux-gnu-g++` (AMD64), `aarch64-linux-gnu-g++` (ARM64), `arm-linux-gnueabihf-g++` (ARM32: ARMv7 hard-float). |
| Importers      | `onnx`, `onnxsim` and `tflite`, including full-integer quantized TFLite models.        |
| Tuning         | What MetaSchedule needs: `xgboost`, `cloudpickle`, `psutil`, `scipy`.                  |
| HTTP client    | `requests`, for direct CORE calls and signed artifact uploads; no DigitalHub SDK. |
| Build record   | `/opt/tvm/provenance.json`: versions, commits and SHA-256 of the TVM libraries.        |

The image is based on `ubuntu:24.04` and published for `linux/amd64` and `linux/arm64`:

| Image variant | CORE target CPU profiles |
| ------------- | ------------------------ |
| `amd64` | `auto`, `amd64`, `amd64_v3`, `amd64_native`, `arm64`, `arm64_pi5`, `arm32` |
| `arm64` | `auto`, `amd64`, `amd64_v3`, `arm64`, `arm64_pi5`, `arm32` |

Only `amd64_native` requires an AMD64 compile node. Both image variants include the
AMD64, ARM64 and ARM32 toolchains; `check_image.py` links an LLVM probe for each one
when building the image. These checks do not execute foreign code.
`auto` uses the compile node's architecture. `amd64` means Intel/AMD 64-bit (x86-64-v2),
`arm64` means ARM 64-bit (AArch64), and `arm32` requires ARMv7 hard-float with NEON.
There is no ARM32 toolkit image. The `arm32` target is cross-compiled on AMD64 or
ARM64 and can run with the matching Go/Rust ARMv7 image. CORE deployment on ARM32
also needs a compatible init image; the default init image is AMD64/ARM64 only.

### Environment variables

| Variable                                | Value                                       |
| --------------------------------------- | ------------------------------------------- |
| `TVM_VERSION`, `TVM_GIT_COMMIT`         | Apache TVM release and commit in the image. |
| `TVM_FFI_VERSION`, `TVM_FFI_GIT_COMMIT` | apache-tvm-ffi release and commit.          |
| `PYTHONPATH`                            | `/opt/tvm/python`                           |
| `LD_LIBRARY_PATH`, `TVM_LIBRARY_PATH`   | `/opt/tvm/lib`                              |

Every compiled model records `TVM_VERSION` and `TVM_GIT_COMMIT` in its `metadata.json`,
and the serve images refuse a model built with another TVM version or commit.

## Use from DigitalHub CORE

`runtime-tvm` uses `tvm-toolkit:0.26.0` by default. To use another image, set on CORE:

| Variable                     | Used by                    |
| ---------------------------- | -------------------------- |
| `RUNTIME_TVM_BUILDER_ONNX`   | `tvm+build`, ONNX models   |
| `RUNTIME_TVM_BUILDER_TFLITE` | `tvm+build`, TFLite models |
| `RUNTIME_TVM_COMPILER`       | `tvm+compile`              |

A Run can override `image`. Tasks hold common Kubernetes settings; TVM options are
per-Run. For example, these are the contents of a compile Run's `spec`:

```yaml
task: tvm+compile://my-project/<task-id>
target_architecture: arm64
optimization:
  target_num_cores: 4
tuning:
  tuning_mode: "off"
resources: {cpu: "4", mem: 8Gi}
```

`profile` chooses the compile node; `target_architecture` chooses the Model's CPU
preset. For conversion and tuning options, see the
[CORE TVM reference](https://github.com/scc-digitalhub/digitalhub-core/tree/main/runtimes/runtime-tvm).
Resource needs depend on the model and tuning parallelism; 4 CPUs and 8 GiB are a
starting point for small models, not a guaranteed limit.

### Targets and linking

CORE owns the catalogue in `runtime-tvm.yaml`. Each preset separates `label`, a
standard TVM `target` mapping, and `linker.command`/`linker.options`. Spring reads
it; CORE supplies the selected target as JSON in `TVM_TARGET`. This image contains
no duplicate target catalogue.

A Run can instead provide an explicit LLVM `target`, with the preset omitted or
set to `auto`. `optimization.cross_cc` chooses its linker;
`optimization.cross_cc_options` passes separate arguments, such as
`["--sysroot=/opt/sysroots/arm64"]`. Paths must exist inside the compile image.
For presets, omitted options inherit the YAML linker arguments; `[]` clears them.

`compile_model.py` resolves the target and links a small LLVM probe before building
the Model. It uses `relax.build` and `export_library` for the final SO. MetaSchedule
candidates use the same linker/options. Local tuning and benchmarks require a
compatible host architecture, ABI and CPU features; `cross_cc` alone does not imply
foreign execution. Otherwise use TVM RPC or apply an existing tuning database.

Model metadata records the effective `target`, `target_triple`, `toolchain` and,
when different, `target_requested`. Go/Rust consume that metadata. Adding a CPU
preset does not supply a missing LLVM backend, toolchain/sysroot or runtime image.
This integration is Linux CPU only; CUDA requires a separate implementation.

### Artifact publication

CORE mounts `publish.py` into the Job. It calls CORE directly over HTTP, obtains
signed URLs, uploads files (including multipart uploads), registers the Model and
verifies the Run output. The Job's `DHCORE_*` credentials are used only for CORE.
The toolkit neither installs nor calls the DigitalHub SDK.

## Versions

**The image tag is the git tag, and it is the Apache TVM version**: tag `0.26.0` builds
`tvm-toolkit:0.26.0` on Apache TVM `0.26.0`. Each architecture also gets its own tag,
such as `0.26.0-amd64` and `0.26.0-arm64`.

| TVM      | apache-tvm-ffi | LLVM |
| -------- | -------------- | ---- |
| `0.24.x` | `0.1.11`       | 18   |
| `0.25.x` | `0.1.12`       | 18   |
| `0.26.x` | `0.1.13.post2` | 18   |

Compile and serve with the same TVM version **and commit**. The build record
identifies the packaged libraries; `check_image.py` verifies their SHA-256 hashes,
imports and native/cross linkers when building the image.

## Release

Push a tag `X.Y.Z` (or `X.Y`): the GitHub Action `.github/workflows/tvm-toolkit-image.yml`
builds and publishes the image. For each architecture, on a native runner, it:

1. compiles Apache TVM `vX.Y.Z` with LLVM;
2. copies the libraries and `python/tvm`, and applies the patches in `patches/`;
3. writes `provenance.json` and builds the image, checking library hashes and imports;
4. pushes `<tag>-<arch>`.

A last job publishes the multi-architecture tag. To rebuild a release, run the workflow by
hand on its tag. A new TVM version first needs its apache-tvm-ffi release in the workflow.

## Patches

These local compatibility/performance patches in `patches/` are applied to the TVM Python package. If one does not apply,
the build stops: an image without it would build fine and fail only at run time.

| Patch                        | Why                                                                                       |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `tflite-quantized-ops.patch` | Lets the TFLite importer convert full-integer quantized models (six operators and a fix). |
| `tirx-parser-stack.patch` | Avoids unused source lookups during TIR parsing, reducing MetaSchedule worker startup time under emulation. |

## Related projects

| Project                                             | Role                                         |
| --------------------------------------------------- | -------------------------------------------- |
| DigitalHub CORE (`runtimes/runtime-tvm`)            | Runs the tasks and mounts the scripts.       |
| DigitalHub TVM Runtime Go (`digitalhub-serverless`) | Default serve image, `tvm-runtime-go`.       |
| DigitalHub TVM Runtime Rust (`digitalhub-tvm-rust`) | Alternative serve image, `tvm-runtime-rust`. |

## Security Policy

The current release is the supported version. Security fixes are released together with all other fixes in each new release.

If you discover a security vulnerability in this project, please do not open a public issue.

Instead, report it privately by emailing us at digitalhub@fbk.eu. Include as much detail as possible to help us understand and address the issue quickly and responsibly.

## Contributing

To report a bug or request a feature, please first check the existing issues to avoid duplicates. If none exist, open a new issue with a clear title and a detailed description, including any steps to reproduce if it's a bug.

To contribute code, start by forking the repository. Clone your fork locally and create a new branch for your changes. Make sure your commits follow the [Conventional Commits v1.0](https://www.conventionalcommits.org/en/v1.0.0/) specification to keep history readable and consistent.

Once your changes are ready, push your branch to your fork and open a pull request against the main branch. Be sure to include a summary of what you changed and why. If your pull request addresses an issue, mention it in the description (e.g., “Closes #123”).

Please note that new contributors may be asked to sign a Contributor License Agreement (CLA) before their pull requests can be merged. This helps us ensure compliance with open source licensing standards.

We appreciate contributions and help in improving the project!

## Authors

This project is developed and maintained by **DSLab – Fondazione Bruno Kessler**, with contributions from the open source community. A complete list of contributors is available in the project’s commit history and pull requests.

For questions or inquiries, please contact: [digitalhub@fbk.eu](mailto:digitalhub@fbk.eu)

## Copyright and license

Copyright © 2025 DSLab – Fondazione Bruno Kessler and individual contributors.

This project is licensed under the Apache License, Version 2.0.
You may not use this file except in compliance with the License. Ownership of contributions remains with the original authors and is governed by the terms of the Apache 2.0 License, including the requirement to grant a license to the project.
