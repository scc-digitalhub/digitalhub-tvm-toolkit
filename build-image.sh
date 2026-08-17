#!/usr/bin/env bash
# Build the tvm-toolkit image (tvm+build / tvm+compile) by packaging the host TVM
# build (stripped .so + python/tvm). Version-parametric via _tvm-version.sh.
#   ./build-image.sh [--load] [--push]
#   TAG=<repo:tag>         image name         (default tvm-toolkit:<version>)
#   REGISTRY=<host[/org]>  push target prefix (the pushed ref is $REGISTRY/$TAG)
#   --load  -> minikube image load (local dev)     --push -> push to the registry
# Remote cluster: build, --push to your registry, then point CORE at the exact
# pushed ref via RUNTIME_TVM_BUILDER_* and RUNTIME_TVM_COMPILER
# (e.g. RUNTIME_TVM_COMPILER=ghcr.io/acme/tvm-toolkit:0.25).
# Requires a locally-built TVM (run ./build-tvm.sh first).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_tvm-version.sh
source "$HERE/_tvm-version.sh"
resolve_tvm_version || exit 1
tvm_assert_built || exit 1

TVM="${TVM:-$TVM_SRC}"
TAG="${TAG:-tvm-toolkit:$TVM_TAG}"
REGISTRY="${REGISTRY:-}" # empty = push bare $TAG; set host[/org] to push for a remote cluster
ctx="$HERE/tvm-toolkit"

LOAD=0; PUSH=0
for a in "$@"; do case "$a" in --load) LOAD=1 ;; --push) PUSH=1 ;; esac; done

[ -f "$TVM/build/lib/libtvm_compiler.so" ] || { echo "missing libtvm_compiler.so in $TVM/build/lib"; exit 1; }

rm -rf "$ctx/lib" "$ctx/python"; mkdir -p "$ctx/lib" "$ctx/python"
# Strip debug symbols: RelWithDebInfo libs are huge (libtvm_compiler ~1.4GB).
for so in libtvm_runtime.so libtvm_ffi.so libtvm_compiler.so; do
  cp "$TVM/build/lib/$so" "$ctx/lib/$so"
  strip --strip-debug "$ctx/lib/$so" 2>/dev/null || true
done
cp -r "$TVM/python/tvm" "$ctx/python/tvm"
find "$ctx/python" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true

# Patches carried on top of the packaged TVM python tree. These must apply cleanly:
# a silently unpatched image builds fine and then fails at run time, so bail out
# instead. Drop a patch here once the same fix lands in the TVM version we package.
for p in "$HERE"/patches/*.patch; do
  [ -e "$p" ] || break
  echo "== applying $(basename "$p") =="
  patch -p1 -d "$ctx/python" --forward --no-backup-if-mismatch < "$p" || {
    echo "FAILED to apply $(basename "$p") to TVM $TVM_VERSION — refusing to build an image without it" >&2
    exit 1
  }
done

echo "== docker build $TAG (tvm-ffi=$TVM_FFI_VERSION llvm=$LLVM_VERSION) =="
docker build -t "$TAG" \
  --build-arg "TVM_FFI_VERSION=$TVM_FFI_VERSION" \
  --build-arg "LLVM_VERSION=$LLVM_VERSION" \
  "$ctx"
rm -rf "$ctx/lib" "$ctx/python"

[ "$LOAD" = 1 ] && { echo ">> minikube image load $TAG"; minikube image load "$TAG"; }
if [ "$PUSH" = 1 ]; then
    ref="${REGISTRY:+$REGISTRY/}$TAG"
    docker tag "$TAG" "$ref"; docker push "$ref"
    echo ">> pushed $ref  (point CORE at it: RUNTIME_TVM_COMPILER / RUNTIME_TVM_BUILDER_*=$ref)"
fi
echo "DONE $TAG"
