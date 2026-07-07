#!/usr/bin/env bash
# Resolve the TVM version + version-coupled deps used by the image builds.
# Source this file, then call resolve_tvm_version; it exports:
#   TVM_VERSION  TVM_SRC  TVM_BUILD  TVM_TAG  TVM_FFI_VERSION  LLVM_VERSION
#
# Override any of:  TVM_VERSION  TVM_FFI_VERSION  LLVM_VERSION  TVM_ROOT
# Default TVM_VERSION = the latest stable release on GitHub IF it is built
# locally under $TVM_ROOT/tvm-<v>; otherwise the highest locally-built stable
# (and it prints a note when a newer stable exists upstream).

TVM_ROOT="${TVM_ROOT:-$HOME/tvm/src}"
# dir of this script (for sibling build-tvm.sh references), resolved at source time
_TVM_DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

_tvm_latest_remote() {
    curl -fsS --max-time 6 https://api.github.com/repos/apache/tvm/releases/latest 2>/dev/null |
        grep -oE '"tag_name": *"v?[0-9.]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# highest locally-COMPILED version (has build/lib/libtvm_runtime.so), not just cloned
_tvm_highest_built() {
    local d
    for d in $(ls -d "$TVM_ROOT"/tvm-[0-9]*.[0-9]*.[0-9]* 2>/dev/null | sort -Vr); do
        [ -f "$d/build/lib/libtvm_runtime.so" ] && { echo "${d##*/tvm-}"; return 0; }
    done
    return 0
}

resolve_tvm_version() {
    if [ -z "${TVM_VERSION:-}" ]; then
        local remote built
        remote="$(_tvm_latest_remote || true)"
        built="$(_tvm_highest_built || true)"
        if [ -n "$remote" ] && [ -f "$TVM_ROOT/tvm-$remote/build/lib/libtvm_runtime.so" ]; then
            TVM_VERSION="$remote"
        elif [ -n "$built" ]; then
            TVM_VERSION="$built"
            if [ -n "$remote" ] && [ "$remote" != "$built" ]; then
                echo ">> nota: latest stabile su GitHub = $remote, uso il build locale $built" >&2
                if [ -d "$TVM_ROOT/tvm-$remote" ]; then
                    echo "         (tvm-$remote è clonato ma NON compilato — compila con ./build-tvm.sh)" >&2
                else
                    echo "         (builda TVM $remote in $TVM_ROOT/tvm-$remote per aggiornare)" >&2
                fi
            fi
        elif [ -n "$remote" ]; then
            # Fresh clone bootstrap: nothing built locally yet, but the latest
            # stable release is known — use it so ./build-tvm.sh can clone+build.
            # Callers that need a built tree still fail via tvm_assert_built.
            TVM_VERSION="$remote"
            echo ">> nota: nessun TVM compilato in $TVM_ROOT — uso il latest stabile $remote (compila con ./build-tvm.sh)" >&2
        else
            echo "ERRORE: nessun TVM compilato in $TVM_ROOT/tvm-X.Y.Z e release remota non determinabile — imposta TVM_VERSION e compila (./build-tvm.sh)" >&2
            return 1
        fi
    fi

    TVM_SRC="$TVM_ROOT/tvm-$TVM_VERSION"
    TVM_BUILD="${TVM_BUILD:-$TVM_SRC/build}"
    TVM_TAG="${TVM_VERSION%.*}" # major.minor → image tag (es. 0.25)

    # version-coupled toolkit deps (override via env if a version differs)
    LLVM_VERSION="${LLVM_VERSION:-18}"
    if [ -z "${TVM_FFI_VERSION:-}" ]; then
        case "$TVM_VERSION" in
            0.24.*) TVM_FFI_VERSION=0.1.11 ;;
            0.25.*) TVM_FFI_VERSION=0.1.12 ;;
            *)
                TVM_FFI_VERSION=0.1.12
                echo ">> nota: apache-tvm-ffi per TVM $TVM_VERSION non noto, default $TVM_FFI_VERSION" >&2
                echo "         (passa TVM_FFI_VERSION=<v> se 3rdparty/tvm-ffi differisce)" >&2
                ;;
        esac
    fi

    export TVM_VERSION TVM_SRC TVM_BUILD TVM_TAG TVM_FFI_VERSION LLVM_VERSION
    echo ">> TVM $TVM_VERSION (src=$TVM_SRC tag=$TVM_TAG ffi=$TVM_FFI_VERSION llvm=$LLVM_VERSION)" >&2
}

# True if the resolved TVM version is compiled (build/lib present).
tvm_is_built() { [ -f "$TVM_BUILD/lib/libtvm_runtime.so" ]; }

# Fail (with how-to) if TVM is not compiled. Call after resolve_tvm_version.
tvm_assert_built() {
    tvm_is_built && return 0
    echo "ERRORE: TVM $TVM_VERSION non compilato ($TVM_BUILD/lib/libtvm_runtime.so manca)." >&2
    echo "        Compilalo con:  $_TVM_DOCKER_DIR/build-tvm.sh" >&2
    return 1
}
