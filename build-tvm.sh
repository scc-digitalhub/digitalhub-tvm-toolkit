#!/usr/bin/env bash
# Build Apache TVM from source for the selected version: clone (if missing) +
# init submodules + cmake + ninja. Idempotent (no-op if already built; FORCE=1
# to reconfigure+rebuild). Heavy (~20-60 min).
#   build-tvm.sh                    # build the resolved/default version
#   TVM_VERSION=0.25.0 build-tvm.sh
#   FORCE=1 build-tvm.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_tvm-version.sh
source "$HERE/_tvm-version.sh"
resolve_tvm_version || exit 1

if tvm_is_built && [ "${FORCE:-0}" != 1 ]; then
    echo "TVM $TVM_VERSION già compilato: $TVM_BUILD/lib (FORCE=1 per ricompilare)"
    exit 0
fi

# prerequisiti di build
miss=()
for t in git cmake ninja "llvm-config-$LLVM_VERSION" g++; do
    command -v "$t" >/dev/null 2>&1 || miss+=("$t")
done
[ "${#miss[@]}" -eq 0 ] || {
    echo "ERRORE: prerequisiti mancanti: ${miss[*]}"
    echo "  es. apt: cmake ninja-build llvm-$LLVM_VERSION libllvm${LLVM_VERSION} g++ git"
    exit 1
}

if [ ! -d "$TVM_SRC" ]; then
    echo ">> clono TVM v$TVM_VERSION in $TVM_SRC"
    git clone --depth 1 --branch "v$TVM_VERSION" --recurse-submodules --shallow-submodules \
        https://github.com/apache/tvm "$TVM_SRC"
else
    echo ">> $TVM_SRC esiste: verifico che sia su v$TVM_VERSION"
    (
        cd "$TVM_SRC"
        cur="$(git describe --tags --exact-match 2>/dev/null || true)"
        if [ "$cur" != "v$TVM_VERSION" ]; then
            echo ">> checkout v$TVM_VERSION (HEAD attuale: ${cur:-sconosciuto})"
            git fetch --depth 1 origin "refs/tags/v$TVM_VERSION:refs/tags/v$TVM_VERSION" \
                || git fetch --tags --depth 1 origin
            git checkout -q "v$TVM_VERSION"
        fi
        git submodule update --init --recursive
    )
fi

mkdir -p "$TVM_BUILD"
cp "$TVM_SRC/cmake/config.cmake" "$TVM_BUILD/config.cmake"
{
    echo "set(USE_LLVM \"llvm-config-$LLVM_VERSION\")"
    echo "set(CMAKE_BUILD_TYPE RelWithDebInfo)"
    echo "set(USE_CCACHE AUTO)"
    echo "set(USE_GTEST OFF)"
} >> "$TVM_BUILD/config.cmake"

echo ">> cmake + ninja in $TVM_BUILD (può richiedere 20-60 min)"
(cd "$TVM_BUILD" && cmake "$TVM_SRC" -G Ninja && ninja -j"$(nproc)")

tvm_is_built || { echo "ERRORE: build completata ma $TVM_BUILD/lib/libtvm_runtime.so manca"; exit 1; }
echo "DONE: TVM $TVM_VERSION compilato → $TVM_BUILD/lib"
