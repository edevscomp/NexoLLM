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
RW_DMG="$(mktemp -u -t nexollm_rw).dmg"
PBBK_BIN="$(mktemp -u -t nexollm_pbbk).bin"
trap 'rm -f "$BG_TIFF" "$RW_DMG" "$PBBK_BIN"' EXIT

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
rm -f "$OUT_DMG" "$RW_DMG"

ICON_ARG=()
if [[ -f Resources/AppIcon.icns ]]; then
    ICON_ARG=(-D "icon=Resources/AppIcon.icns")
fi

# 1. Build writable HFS+ image first so we can inject native Apple URL.bookmarkData() for macOS 26 Tahoe+
"$VENV_DIR/bin/dmgbuild" \
    -s scripts/dmg-settings.py \
    -D "format=UDRW" \
    -D "app=$APP_PATH" \
    -D "background=$BG_TIFF" \
    "${ICON_ARG[@]}" \
    "$VOL_NAME" \
    "$RW_DMG"

# 2. Mount the writable HFS+ volume and replace synthetic mac_alias pBBk with real Foundation URL.bookmarkData()
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil attach -readwrite -noverify -noautoopen -quiet "$RW_DMG"

swift - "$MOUNT_DIR/.background.tiff" "$PBBK_BIN" <<'SWIFT'
import Foundation
let bgURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let data = try bgURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
try data.write(to: outURL)
SWIFT

"$VENV_DIR/bin/python" - "$MOUNT_DIR" "$PBBK_BIN" <<'PY'
import sys
from ds_store import DSStore
from mac_alias import Alias

mount_dir, pbbk_path = sys.argv[1], sys.argv[2]
bg_path = f"{mount_dir}/.background.tiff"
ds_path = f"{mount_dir}/.DS_Store"

with open(pbbk_path, "rb") as f:
    native_pbbk = f.read()

class RawBookmark:
    def __init__(self, data: bytes):
        self.data = data
    def to_bytes(self) -> bytes:
        return self.data

native_alias = Alias.for_file(bg_path).to_bytes()

with DSStore.open(ds_path, "r+") as d:
    d["."]["pBBk"] = RawBookmark(native_pbbk)
    icvp = dict(d["."]["icvp"])
    icvp["backgroundType"] = 2
    icvp["backgroundColorRed"] = 0.075
    icvp["backgroundColorGreen"] = 0.082
    icvp["backgroundColorBlue"] = 0.125
    icvp["backgroundImageAlias"] = native_alias
    d["."]["icvp"] = icvp
    d.flush()
PY

sync
hdiutil detach "$MOUNT_DIR" -force -quiet

# 3. Convert writable HFS+ image to compressed read-only UDZO (preserves HFS+ volume UUID & CNIDs)
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -quiet -o "$OUT_DMG"

echo "Created styled DMG: $OUT_DMG"
