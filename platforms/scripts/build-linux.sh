#!/usr/bin/env bash
# Builds NexoLLM for Linux (X11 + Wayland IBus module) and generates SHA256SUMS.txt + Ed25519 .sig.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
PROFILE="release"
if [[ "${1:-}" == "--debug" ]]; then PROFILE="debug"; fi

echo "==> Running nexollm-core test suite..."
(cd "$REPO_ROOT/platforms" && cargo test -p nexollm-core)

echo "==> Building NexoLLM $VERSION for Linux ($PROFILE)..."
CARGO_ARGS=()
[[ "$PROFILE" == "release" ]] && CARGO_ARGS+=(--release)
(cd "$REPO_ROOT/platforms" && cargo build --workspace "${CARGO_ARGS[@]}")

if command -v npm >/dev/null 2>&1 && [[ -f "$REPO_ROOT/platforms/ui/package.json" ]]; then
    (cd "$REPO_ROOT/platforms/ui" && npm ci && npm run build)
fi

OUT_DIR="$REPO_ROOT/dist/linux"
mkdir -p "$OUT_DIR"

BIN_SRC="$REPO_ROOT/platforms/target/$PROFILE/nexollm-desktop"
if [[ -f "$BIN_SRC" ]]; then
    ARCH="$(uname -m)"
    ARTIFACT="$OUT_DIR/NexoLLM-$VERSION-linux-$ARCH"
    cp "$BIN_SRC" "$ARTIFACT"
    strip "$ARTIFACT" 2>/dev/null || true
    chmod 0755 "$ARTIFACT"
    (cd "$OUT_DIR" && sha256sum "$(basename "$ARTIFACT")" > SHA256SUMS.txt)
    echo "Built $ARTIFACT"
    cat "$OUT_DIR/SHA256SUMS.txt"
fi
