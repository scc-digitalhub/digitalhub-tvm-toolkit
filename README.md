# DigitalHub TVM Toolkit

The image **`ghcr.io/scc-digitalhub/tvm-toolkit`** contains [Apache TVM](https://tvm.apache.org/)
and the tools around it. DigitalHub CORE (`runtime-tvm`) runs it for two tasks:

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
The older CORE names (`cpu`/`llvm`, `x86`, `x86_v3`, `x86_native`, `armv7l`) remain
accepted aliases; LLVM triples and toolchain names have not changed. The toolkit has
no ARM32 image: the ARM32 profile is cross-compiled from one of the two image variants.
Both Go and Rust runtime image builds cover AMD64, ARM64 and ARMv7; ARM32 compilation
and inference remain supported. Serving through CORE on an ARM32 node additionally
requires an ARMv7-compatible init image: CORE's default init image covers only AMD64
and ARM64. Running the compiler on ARM32 is separate and has no toolkit image.

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

A single run can also set `image`. Build conversion flags, compile targets and tuning
are CORE **run** options, not reusable task settings. Tasks retain common resources,
profiles, environment variables, secrets and volumes. CORE passes the run options
to the scripts through environment variables.

### Configurable targets

CORE reads profiles from `runtime-tvm.yaml`: `target` contains standard TVM options
as a YAML mapping; `linker.command` and `linker.options` configure the C++ linker.
CORE converts the target to the same JSON consumed by the compile script, preserving
lists and numbers. The toolkit does not duplicate this catalogue. A run can select
a configured `target_architecture`, or pass an explicit standard LLVM `target` object.

`optimization.cross_cc` selects the compiler; `optimization.cross_cc_options` is an
array of arguments such as `["--sysroot=/opt/sysroots/arm64"]`. Paths refer to the
compile container. For another architecture, supply a compatible compile image with
the required LLVM backend, toolchain and libraries. A new profile alone does not add
those tools or a serving image.

CORE checks the toolchain by linking a small LLVM object before compiling the model.
Local tuning and benchmarks require a compatible host architecture, ABI and CPU
features; setting `cross_cc` alone does not disable them. MetaSchedule candidates and
the final library use the same compiler options; RPC devices load the linked candidates.
CUDA and other device backends are not part of this CPU pipeline.

Build and compile scripts call CORE directly over HTTP. CORE supplies signed upload
URLs and selects the storage location; the scripts upload the files, register the
Model and verify its run output. Large files use CORE's multipart upload endpoints.
The image does not install or call the DigitalHub SDK. CORE authentication uses the
Job's existing `DHCORE_*` environment variables; credentials are not forwarded to storage.

Tips:

- **Memory.** Give `tvm+compile` at least `mem: 8Gi` and `cpu: 4`, or the Job may be
  killed (exit code 137).
- **Speed.** Untuned CPU code is slow: tune the model with MetaSchedule. The
  `runtime-tvm` README explains how and lists all the run options.

## Versions

**The image tag is the git tag, and it is the Apache TVM version**: tag `0.26.0` builds
`tvm-toolkit:0.26.0` on Apache TVM `0.26.0`. Each architecture also gets its own tag,
such as `0.26.0-amd64` and `0.26.0-arm64`.

| TVM      | apache-tvm-ffi | LLVM |
| -------- | -------------- | ---- |
| `0.24.x` | `0.1.11`       | 18   |
| `0.25.x` | `0.1.12`       | 18   |
| `0.26.x` | `0.1.13.post2` | 18   |

Compile and serve with images of the same release.

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

The patches in `patches/` are applied to the TVM Python package. If one does not apply,
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
