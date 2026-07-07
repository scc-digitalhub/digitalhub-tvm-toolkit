# Toolkit TVM per build (onnx→IR) e compile (IR→model.so). La VERSIONE non è
# cablata qui: è quella del build host impacchettato (vedi build-image.sh /
# _tvm-version.sh) — coerente col runtime di serving Rust della stessa versione.
#
# Impacchetta il build host di TVM (lib .so + python/tvm) invece di ricompilare
# da sorgente in-image. Base ubuntu:24.04 per combaciare con la glibc/libstdc++
# dell'host di build. Le .so sono già strippate da build-image.sh.
FROM ubuntu:24.04

# Version-coupled deps (passed by build-image.sh from the resolved TVM version):
#   LLVM_VERSION     libLLVM major (TVM codegen needs the matching libLLVM.so)
#   TVM_FFI_VERSION  apache-tvm-ffi pip version bundled in this TVM (3rdparty/tvm-ffi)
ARG LLVM_VERSION=18
ARG TVM_FFI_VERSION=0.1.11

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python-is-python3 libstdc++6 libgomp1 ca-certificates git \
        libllvm${LLVM_VERSION} \
        gcc g++ \
        g++-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*
# libllvm18 fornisce libLLVM.so.18.1, richiesta da libtvm_compiler.so (codegen LLVM).
# gcc/g++ nativi: servono a tvm.contrib.cc.create_shared (export_library) per LINKARE
# la model.so del target host (llvm x86_64). Senza, get_cc()=None → TypeError nel link.
# NB: cross-toolchain ARM64 → una sola immagine compila per x86_64, aarch64 (LLVM).

# TVM nativo (dal build host risolto, vedi build-image.sh / _tvm-version.sh)
COPY lib/ /opt/tvm/lib/
COPY python/ /opt/tvm/python/

ENV LD_LIBRARY_PATH=/opt/tvm/lib \
    PYTHONPATH=/opt/tvm/python \
    TVM_LIBRARY_PATH=/opt/tvm/lib

# deps Python: tvm-ffi (matching TVM) + onnx + ml_dtypes + l'SDK digitalhub (per pubblicare i Model)
RUN pip3 install --no-cache-dir --break-system-packages \
        apache-tvm-ffi==${TVM_FFI_VERSION} onnx ml_dtypes numpy scipy cloudpickle \
        typing_extensions psutil tornado packaging decorator attrs \
        digitalhub \
    && python3 -c "import tvm; print('tvm', tvm.__version__); import onnx, digitalhub; print('onnx+sdk ok')"
