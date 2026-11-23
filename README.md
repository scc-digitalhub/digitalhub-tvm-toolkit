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
| Apache TVM     | Compiler and runtime libraries in `/opt/tvm/lib`, Python package in `/opt/tvm/python`, C headers in `/opt/tvm/include`. |
| apache-tvm-ffi | Python wheel linked to the `libtvm_ffi.so` of the same TVM build.                      |
| LLVM           | `libllvm18`, used by TVM to generate the code.                                         |
| C++ compilers  | Native `g++`, `x86_64-linux-gnu-g++` (AMD64), `aarch64-linux-gnu-g++` (ARM64), `arm-linux-gnueabihf-g++` (ARM32: ARMv7 hard-float). |
| Importers      | `onnx`, `onnx-ir`, `onnxsim` and `tflite`, including full-integer quantized TFLite models.        |
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

Use `ghcr.io/scc-digitalhub/tvm-toolkit:0.26.0-r2` for the current TVM 0.26.0
toolkit release. The configured default depends on the CORE release. To select
the image explicitly, set these variables on CORE:

| Variable                     | Used by                    |
| ---------------------------- | -------------------------- |
| `RUNTIME_TVM_BUILDER_ONNX`   | `tvm+build`, ONNX models   |
| `RUNTIME_TVM_BUILDER_TFLITE` | `tvm+build`, TFLite models |
| `RUNTIME_TVM_COMPILER`       | `tvm+compile`              |

Update the Go/Rust serving image to receive request-validation fixes. Existing
valid models can be reused when the runtime uses the same TVM version and commit
and the model's target, metadata and datatypes remain compatible. These serving
fixes do not require a new toolkit image.

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

`profile` chooses the compile node; `target_architecture` chooses the Model's target
preset. For conversion and tuning options, see the
[CORE TVM reference](https://github.com/scc-digitalhub/digitalhub-core/tree/main/runtimes/runtime-tvm).
Resource needs depend on the model and tuning parallelism; 4 CPUs and 8 GiB are a
starting point for small models, not a guaranteed limit.

### Targets and linking

CORE owns the catalogue in `runtime-tvm.yaml`. Each preset separates `label`, a
standard TVM `target` encoded as a JSON string, and `linker.command`/`linker.options`.
The shared YAML reader loads it; CORE supplies the selected JSON in `TVM_TARGET`.
JSON preserves arrays, numbers and nested options. This image contains no duplicate
target catalogue.

A Run can instead provide an explicit LLVM or CUDA `target` object, with the preset omitted
or set to `auto`. Only the YAML catalogue uses a JSON string.
`optimization.cross_cc` chooses its linker;
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
The default images are Linux CPU builds. An optional CUDA toolkit is
available as a separate local build, described below.

### Optional CUDA toolkit

The CUDA variant extends the pinned TVM `0.26.0-r2` CPU image. It adds NVIDIA's
CUDA 13.2.1 `nvcc` and runtime packages, plus the upstream
`libtvm_runtime_cuda.so` built at TVM commit
`c7b458e946bc4266915da582457476bdcd9705ae`, with its matching FFI submodule
`12dbf053b3d9ba4ebd9da3123b1aeca79cf74229`. It uses the existing compiler,
patched Python tree and cross-compilers from the same TVM revision. The default
CPU image and publishing workflow remain independent of this variant.

Build on a native AMD64 or ARM64 machine; choose the matching local tag:

```bash
docker build -f tvm-toolkit/Dockerfile.cuda \
  --build-arg TVM_CUDA_BUILD_JOBS=2 \
  -t local/tvm-toolkit:0.26.0-cuda13.2.1-amd64 tvm-toolkit
```

`TOOLKIT_IMAGE` can override the pinned, multiarchitecture CPU base. Its TVM/FFI
versions and commits must match the CUDA sidecar. `TVM_CUDA_BUILD_JOBS` limits the
sidecar build's parallelism. No upstream TVM source changes are applied.

The baseline environment is `TVM_CUDA_COMPILE_MODE=nvcc` and
`TVM_CUDA_NVCC_NO_FAST_MATH=1`. The default loader path is
`/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/opt/tvm/lib:/usr/local/cuda/lib64`.
The image attests `compiled_backends` as
`["cpu", "cuda"]`; its build record includes the sidecar's SHA-256, source
commits, effective CUDA CMake cache and installed CUDA package versions. The
sidecar is checked against the inherited runtime and FFI libraries.

Compilation without a GPU requires an explicit opt-in to NVIDIA's driver stub:

```bash
docker run --rm --network none \
  -e LD_LIBRARY_PATH=/opt/tvm/cuda-driver-stubs:/opt/tvm/lib:/usr/local/cuda/lib64 \
  local/tvm-toolkit:0.26.0-cuda13.2.1-amd64 \
  python3 /opt/tvm/check_cuda.py --require-no-gpu
```

The stub is isolated in `/opt/tvm/cuda-driver-stubs/libcuda.so.1` and is absent
from the default loader path. Keep that path out of GPU execution environments
and serving images. A real GPU uses the host's NVIDIA driver and container
runtime. CPU compilation works with the normal loader path and needs no NVIDIA
driver or device.

`check_cuda.py` compiles CUDA `sm_87` add and matmul kernels, then uses standard
`export_library` for explicit LLVM AMD64 and ARM64 hosts. It checks each host
ELF architecture, requires the real CUDA runtime factory and runnable module
property, and reloads the native-host artifact with `nvcc` removed from `PATH`.
It rejects TVM's raw CUDA source fallback. These are compilation and serialization
checks; they do not run a kernel or validate numerical results on a GPU.

The manual-only `tvm-toolkit-cuda.yml` workflow builds and checks both native host
architectures and uploads build evidence. It has no registry publishing steps.
CUDA toolkit images have no published release tag yet. Jetson Orin `sm_87` with
JetPack 7.2 / L4T 39.2 / Ubuntu 24.04 / CUDA 13.2.1 is the intended hardware
baseline; hardware execution, numerics and performance remain **NOT_RUN**. NVIDIA's
[JetPack 7.2 release information](https://developer.nvidia.com/embedded/jetpack/downloads/archive-7.2)
lists that vendor stack. See also the
[CUDA 13.2.1 image definitions](https://gitlab.com/nvidia/container-images/cuda/-/tree/master/dist/13.2.1/ubuntu2404).

CORE's `jetson_orin_cuda` preset uses standard TVM JSON with a nested host:

```json
{"kind":"cuda","arch":"sm_87","host":{"kind":"llvm","mtriple":"aarch64-linux-gnu"}}
```

For an AMD64 host, use `x86_64-linux-gnu` and the actual GPU's `sm_...` architecture.
Offline `off`/`apply` compilation needs no GPU measurements; active tuning requires
real GPU limits from `Target.from_device` and local device access or the existing
RPC runner. CORE's Run/Task `envs` can supply the explicit stub loader path for
offline compilation. Select `image` separately from the model target and node
`profile`; CUDA compilation does not select a serving image or GPU node. The
[CUDA guide](https://scc-digitalhub.github.io/docs/0.16/runtimes/tvm/#cuda-fp32-optional)
contains complete CORE examples and benchmark semantics.

For the current Orin ARM64 base, install NVIDIA Container Toolkit **1.19.1 or newer**
on the host and verify `nvidia-ctk --version`. The
[1.19.1 release](https://github.com/NVIDIA/nvidia-container-toolkit/releases/tag/v1.19.1)
fixes the compatibility-header failure reproduced with 1.19.0. The hook runs before
the container entrypoint; image environment changes do not replace the host update.

The builder includes `onnx-ir==1.1.0` for standard ONNX topological sorting in CORE's
production script, including subgraphs. Original Model files are preserved.

### Artifact publication

CORE mounts `publish.py` into the Job. It uses `requests` for direct CORE HTTP calls
and signed storage uploads, including multipart uploads. The Job's `DHCORE_*`
credentials are used only for CORE. The toolkit has no DigitalHub SDK dependency.

A CORE build containing the publisher update in
[PR #254](https://github.com/scc-digitalhub/digitalhub-core/pull/254) follows this lifecycle:

1. Register the Model in `CREATED` with its storage path, then set it to `UPLOADING`.
2. Upload each artifact and retrieve its file information. Store up to 100 file
   records in `status.files`; larger sets use CORE's external file index with an
   empty `status.files`.
3. Mark the Model `READY`, then write and verify the Run output: `ir_module` for
   build or `compiled_so` for compile.

Upload or file-indexing failures attempt to mark the Model `ERROR`. A Run-output
failure leaves the Model `READY` and reports an error. This lifecycle requires a
CORE build containing the publisher update; changing the toolkit image alone does
not update the mounted scripts.

## Versions

The image tag identifies a toolkit release: `tvm-toolkit:0.26.0-r2` packages Apache
TVM `0.26.0`. Each architecture also gets its own tag, such as `0.26.0-r2-amd64` and
`0.26.0-r2-arm64`. A new toolkit revision can keep the same Apache TVM version.

| TVM      | apache-tvm-ffi | LLVM |
| -------- | -------------- | ---- |
| `0.24.x` | `0.1.11`       | 18   |
| `0.25.x` | `0.1.12`       | 18   |
| `0.26.x` | `0.1.13.post2` | 18   |

Compile and serve with the same TVM version **and commit**. The build record
identifies the packaged libraries; `check_image.py` verifies their SHA-256 hashes,
imports and native/cross linkers when building the image. It also records the toolkit
repository, source commit and image tag; `org.digitalhub.source.revision` labels the
toolkit commit separately from the Apache TVM commit.

## Release

To publish the current toolkit from `main` with an unchanged Apache TVM version:

```bash
gh workflow run tvm-toolkit-image.yml \
  --repo scc-digitalhub/digitalhub-tvm-toolkit \
  --ref main \
  -f tvm_version=0.26.0 \
  -f image_tag='<new-image-tag>'
```

Replace `<new-image-tag>` with an unused tag. This command builds and publishes
images to GHCR. Manual releases require `main`, a TVM version `X.Y.Z` and a Docker
image tag of at most 122 characters, leaving room for the architecture suffix.

Pushing a Git tag `X.Y.Z` or `X.Y` still builds the matching Apache TVM release and
uses that Git tag as the image tag (`0.26` selects TVM `0.26.0`). Neither path moves
existing Git tags. A new TVM version needs its apache-tvm-ffi mapping in the workflow.

For each architecture, on a native runner, the workflow:

1. checks out the toolkit commit that triggered the run and compiles the selected Apache TVM release with LLVM;
2. copies the libraries, C headers and `python/tvm`, and applies the patches in `patches/`;
3. writes `provenance.json` and builds the image, checking library hashes and imports;
4. pushes `<tag>-<arch>` and saves its published digest.

A last job checks the source commit and matching TVM/FFI labels, then publishes the
multi-architecture tag from those exact digests. Failed architecture jobs can be retried;
the final image is published only when both architectures succeed.
To use a new release in CORE, update the three builder/compiler variables listed above
or set `image` on the Run. Publishing an image does not change CORE's default.

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

Local CPU builds retain a separate build context, printed by `build-image.sh`;
`TVM_BUILD_CONTEXT` can select a new directory. Existing repository artifacts are
preserved. CPU publishing rejects CUDA tags. Publication checks every architecture
and manifest tag and refuses existing tags or ambiguous registry errors. Select a
new release tag when publishing rebuilt sources. The CUDA toolkit workflow remains
validation-only.
