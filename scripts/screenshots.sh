#!/bin/bash
# Renders the README images (light and dark) from the built app into showcase/assets/.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="build/NexoLLM.app/Contents/MacOS/NexoLLM"
test -x "$BIN" || ./build.sh
OUT="$(mktemp -d)"
for theme in light dark; do "$BIN" --render-ui "$OUT" "$theme" >/dev/null 2>&1 || true; done
for name in hero alternatives quickmenu lookup settings-models settings-setup settings-personalization settings-context; do
    for theme in light dark; do cp "$OUT/$name-$theme.png" "showcase/assets/$name-$theme.png"; done
done
rm -rf "$OUT"
echo "Screenshots updated in showcase/assets/"
