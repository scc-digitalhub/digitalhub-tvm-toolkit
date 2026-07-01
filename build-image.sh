#!/usr/bin/env bash
# Build the tvm-toolkit image (tvm+build / tvm+compile) by packaging the host TVM
# build (stripped .so + python/tvm). Version-parametric via _tvm-version.sh.
#   ./build-image.sh [--load] [--push]
# Requires a locally-built TVM (run ./build-tvm.sh first).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_tvm-version.sh
source "$HERE/_tvm-version.sh"
resolve_tvm_version || exit 1
tvm_assert_built || exit 1

TVM="${TVM:-$TVM_SRC}"
TAG="${TAG:-tvm-toolkit:$TVM_TAG}"
REGISTRY="${REGISTRY:-192.168.49.1:5000}"
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

echo "== docker build $TAG (tvm-ffi=$TVM_FFI_VERSION llvm=$LLVM_VERSION) =="
docker build -t "$TAG" \
  --build-arg "TVM_FFI_VERSION=$TVM_FFI_VERSION" \
  --build-arg "LLVM_VERSION=$LLVM_VERSION" \
  "$ctx"
rm -rf "$ctx/lib" "$ctx/python"

[ "$LOAD" = 1 ] && { echo ">> minikube image load $TAG"; minikube image load "$TAG"; }
[ "$PUSH" = 1 ] && { docker tag "$TAG" "$REGISTRY/$TAG"; docker push "$REGISTRY/$TAG"; }
echo "DONE $TAG"
