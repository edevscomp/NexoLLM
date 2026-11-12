#!/bin/bash
# Regenerates the README showcase media in showcase/assets/ from NexoLLM's own SwiftUI views,
# composited onto an atmospheric desktop wallpaper with frosted glass and soft elevation shadows.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
BIN="build/NexoLLM.app/Contents/MacOS/NexoLLM"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NEXO_DEMO_FRAMES=90 NEXO_FAST_MEDIA=1 "$BIN" --render-ui "$WORK" dark >/dev/null 2>&1 || true

python3 scripts/readme_media.py "$WORK" showcase/assets
cp build/NexoLLM.app/Contents/Resources/AppIcon.icns /tmp/nexo_icon.icns
sips -s format png -z 256 256 /tmp/nexo_icon.icns --out showcase/assets/icon.png >/dev/null 2>&1 || true
rm -f /tmp/nexo_icon.icns
echo "Done: regenerated showcase/assets/{icon.png,live.gif,overlays.png,insights.png,settings.png,memory.png}"
