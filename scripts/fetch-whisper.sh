#!/bin/bash
# Downloads the prebuilt whisper.cpp (Metal) xcframework used by the optional Audio Context plugin into Vendor/.
# Pinned to the release NexoLLM is tested with, and verified against its SHA-256 before unpacking.
# To upgrade: change WHISPER_TAG and WHISPER_SHA256 together (shasum -a 256 the new zip).
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_TAG="${WHISPER_TAG:-b5454}"
WHISPER_SHA256="${WHISPER_SHA256:-e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b}"
ZIP="whisper-$WHISPER_TAG-xcframework.zip"
URL="https://github.com/ggml-org/whisper.cpp/releases/download/$WHISPER_TAG/$ZIP"

mkdir -p Vendor/whisper
cd Vendor/whisper
echo "Downloading $URL"
curl -fL --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors -sS -o "$ZIP" "$URL"
actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [[ "$actual" != "$WHISPER_SHA256" ]]; then
    rm -f "$ZIP"
    echo "checksum mismatch for $ZIP" >&2
    echo "  expected $WHISPER_SHA256" >&2
    echo "  got      $actual" >&2
    exit 1
fi
rm -rf build-apple
unzip -q "$ZIP"
rm "$ZIP"
test -d build-apple/whisper.xcframework || { echo "unexpected archive layout" >&2; ls -R | head -40 >&2; exit 1; }
echo "whisper.cpp $WHISPER_TAG verified and ready in Vendor/whisper/build-apple/whisper.xcframework"
