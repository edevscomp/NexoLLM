#!/bin/bash
# Builds a custom-styled Retina DMG installer with Aurora/Glass background, custom volume icon,
# and pre-arranged Finder icon positions (NexoLLM.app -> Applications).
#   scripts/build-dmg.sh <app_path> <out_dmg> <vol_name> <version>
set -euo pipefail
cd "$(dirname "$0")/.."

APP_PATH="${1:?usage: build-dmg.sh <app_path> <out_dmg> <vol_name> <version>}"
OUT_DMG="${2:?}"
VOL_NAME="${3:-NexoLLM}"
VERSION="${4:-0.9.0}"
APP_NAME="$(basename "$APP_PATH")"

STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -u -t nexollm_rw).dmg"
trap 'rm -rf "$STAGE" "$RW_DMG"' EXIT

mkdir -p "$STAGE/.background"
swift scripts/make-dmg-background.swift "$STAGE/.background/background.tiff" "build/dmg-background-preview.png" "$VERSION"

cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
fi

# Unmount any stale volume with the same name
if [[ -d "/Volumes/$VOL_NAME" ]]; then
    hdiutil detach "/Volumes/$VOL_NAME" -force -quiet 2>/dev/null || true
fi

hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$RW_DMG"

ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEV_NAME="$(echo "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT_DIR="$(echo "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"

if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]] && command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

# Configure Finder window layout (bounds, icon size, background picture, icon coordinates)
osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 860, 608}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 108
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$APP_NAME" of container window to {185, 206}
        set position of item "Applications" of container window to {475, 206}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
    chflags hidden "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

sync
hdiutil detach "$DEV_NAME" -quiet || hdiutil detach "$DEV_NAME" -force -quiet
rm -f "$OUT_DMG"
hdiutil convert "$RW_DMG" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG"
echo "Created styled DMG: $OUT_DMG"
