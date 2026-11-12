#!/bin/bash
# Builds a custom-styled Retina DMG installer with Aurora/Glass background, custom volume icon,
# and deterministic binary .DS_Store layout (bwsp, icvp, pBBk, Iloc) via dmgbuild — no Finder
# AppleScript / TCC permissions required (works identically on local Macs and headless GitHub CI).
#   scripts/build-dmg.sh <app_path> <out_dmg> <vol_name> <version>
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="${1:?usage: build-dmg.sh <app_path> <out_dmg> <vol_name> <version>}"
OUT_DMG="${2:?}"
VOL_NAME="${3:-NexoLLM}"
VERSION="${4:-0.9.1}"

BG_TIFF="$(mktemp -u -t nexollm_bg).tiff"
trap 'rm -f "$BG_TIFF"' EXIT

swift scripts/make-dmg-background.swift "$BG_TIFF" "build/dmg-background-preview.png" "$VERSION" >/dev/null

VENV_DIR=".build/dmg-venv"
if [[ ! -x "$VENV_DIR/bin/dmgbuild" ]]; then
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check dmgbuild
fi

# Detach any mounted volume with the same name so dmgbuild can attach cleanly
if [[ -d "/Volumes/$VOL_NAME" ]]; then
    hdiutil detach "/Volumes/$VOL_NAME" -force -quiet 2>/dev/null || true
fi

mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"

ICON_ARG=()
if [[ -f Resources/AppIcon.icns ]]; then
    ICON_ARG=(-D "icon=Resources/AppIcon.icns")
fi

"$VENV_DIR/bin/dmgbuild" \
    -s scripts/dmg-settings.py \
    -D "app=$APP_PATH" \
    -D "background=$BG_TIFF" \
    "${ICON_ARG[@]}" \
    "$VOL_NAME" \
    "$OUT_DMG"

echo "Created styled DMG: $OUT_DMG"
