#!/bin/bash
# Downloads the prebuilt llama.cpp (Metal) xcframework NexoLLM links against into Vendor/.
# Pinned to the release NexoLLM is tested with, and verified against its SHA-256 before unpacking.
# To upgrade: change LLAMA_TAG and LLAMA_SHA256 together (shasum -a 256 the new zip).
set -euo pipefail
cd "$(dirname "$0")/.."

LLAMA_TAG="${LLAMA_TAG:-b11721}"
LLAMA_SHA256="${LLAMA_SHA256:-9efc8f94a7fb54abb4931bac484a025417cee5bbf8e15ba49b4d9ddef997460f}"
ZIP="llama-$LLAMA_TAG-xcframework.zip"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/$ZIP"

mkdir -p Vendor
cd Vendor
echo "Downloading $URL"
curl -fL --proto '=https' --tlsv1.2 --retry 3 --progress-bar -o "$ZIP" "$URL"
actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$actual" != "$LLAMA_SHA256" ]]; then
    rm -f "$ZIP"
    echo "checksum mismatch for $ZIP" >&2
    echo "  expected $LLAMA_SHA256" >&2
    echo "  got      $actual" >&2
    exit 1
fi
rm -rf build-apple
unzip -q "$ZIP"
rm "$ZIP"
test -d build-apple/llama.xcframework || { echo "unexpected archive layout" >&2; exit 1; }
echo "llama.cpp $LLAMA_TAG verified and ready in Vendor/build-apple/llama.xcframework"
