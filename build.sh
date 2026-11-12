#!/bin/bash
# Builds build/NexoLLM.app (release) and signs it.
#   ./build.sh            build only (developer build)
#   ./build.sh install    build, then replace /Applications/NexoLLM.app and relaunch it
#   ./build.sh dist       public build: dist/NexoLLM-<version>.dmg + .zip, ready for GitHub Releases
#
# Every build is compiled without debug info, stripped of local symbols and signed with the hardened
# runtime, so the app can't be patched or injected with libraries. Only `dist` is meant to leave this Mac:
# it's signed with a "Developer ID Application" certificate when one is in the Keychain, else ad hoc; override with CODESIGN_IDENTITY.
#
# Versioning: CFBundleShortVersionString comes from the VERSION file (bump it with scripts/bump.sh),
# CFBundleVersion is the number of commits, so it goes up by itself with every change.
# Signing developer builds with a stable identity keeps the Accessibility permission across rebuilds.
#
# Notarization (needs the $99/yr Apple Developer Program and a "Developer ID Application" certificate):
#   one time:  xcrun notarytool store-credentials "NexoLLM-Notary" --apple-id <email> --team-id <TEAMID> --password <app-specific-password>
#   release:   NOTARY_PROFILE="NexoLLM-Notary" ./build.sh dist
# Without the certificate, `dist` stays ad hoc (downloads show the "unidentified developer" warning).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-build}"
NAME="NexoLLM"

if [[ ! -d Vendor/build-apple/llama.xcframework ]]; then
    echo "llama.cpp framework missing, fetching it..."
    scripts/fetch-llama.sh
fi
if [[ ! -d Vendor/whisper/build-apple/whisper.xcframework ]]; then
    echo "whisper.cpp framework missing, fetching it..."
    scripts/fetch-whisper.sh
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
# 13 builds were made before the current history started; keep counting from there.
BUILD=$(( $(git rev-list --count HEAD 2>/dev/null || echo 0) + 13 ))
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then BUILD=$((BUILD + 1)); fi   # uncommitted work = next build

SWIFT_FLAGS=(-c release -Xswiftc -gnone)
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
strip "$APP/Contents/MacOS/$NAME"   # every symbol the loader doesn't need
cp -R Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework "$APP/Contents/Frameworks/"
cp -R Vendor/whisper/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework "$APP/Contents/Frameworks/"
for FW in llama whisper; do
    rm -rf "$APP/Contents/Frameworks/$FW.framework/Headers" "$APP/Contents/Frameworks/$FW.framework/Modules" \
           "$APP/Contents/Frameworks/$FW.framework/Versions/A/Headers" "$APP/Contents/Frameworks/$FW.framework/Versions/A/Modules"
done
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/ThirdPartyNotices.txt Resources/key-click.wav LICENSE CHANGELOG.md "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

if [[ "$MODE" == "dist" ]]; then
    IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
    IDENTITY="${IDENTITY:--}"
else
    IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
    IDENTITY="${IDENTITY:--}"
fi
ENTITLEMENTS=(--entitlements Resources/App.entitlements)   # microphone (Audio Context plugin, opt-in)
TIMESTAMP=(--timestamp=none)
if [[ "$IDENTITY" == "-" ]]; then
    # Ad hoc signatures have no Team ID, so the hardened runtime's library validation would refuse the
    # bundled llama.framework. Only that check is relaxed; injection through DYLD_* variables stays blocked.
    ENTITLEMENTS=(--entitlements Resources/AdHoc.entitlements)
elif [[ "$MODE" == "dist" ]]; then
    TIMESTAMP=(--timestamp)   # notarization requires a secure timestamp
fi
echo "Signing with: $([[ "$IDENTITY" == "-" ]] && echo "ad hoc" || echo "$IDENTITY")"
codesign --force "${TIMESTAMP[@]}" --options runtime --sign "$IDENTITY" "$APP/Contents/Frameworks/llama.framework"
codesign --force "${TIMESTAMP[@]}" --options runtime --sign "$IDENTITY" "$APP/Contents/Frameworks/whisper.framework"
codesign --force "${TIMESTAMP[@]}" --options runtime ${ENTITLEMENTS[@]+"${ENTITLEMENTS[@]}"} --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP, version $VERSION ($BUILD)"

case "$MODE" in
install)
    pkill -x "$NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$NAME.app"
    open "/Applications/$NAME.app" || true
    ;;
dist)
    OUT="dist"
    rm -rf "$OUT" && mkdir -p "$OUT"
    chmod +x scripts/build-dmg.sh
    DMG_FILE="$NAME-macos.dmg"
    ./scripts/build-dmg.sh "$APP" "$OUT/$DMG_FILE" "$NAME" "$VERSION"
    if [[ "$IDENTITY" != "-" ]]; then
        codesign --force --timestamp --sign "$IDENTITY" "$OUT/$DMG_FILE"
        if [[ -n "${NOTARY_PROFILE:-}" ]]; then
            echo "Submitting to Apple's notary service (profile: $NOTARY_PROFILE)..."
            xcrun notarytool submit "$OUT/$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
            xcrun stapler staple "$OUT/$DMG_FILE"
        fi
    fi
    (cd "$OUT" && shasum -a 256 "$DMG_FILE" > SHA256SUMS.txt)
    # Ed25519 signature the app verifies before opening an update (key in the maintainer's Keychain).
    if [[ "${SKIP_SIGNING:-}" != "1" ]]; then
        swift scripts/release-signing.swift sign "$OUT/$DMG_FILE" "$VERSION" > "$OUT/$DMG_FILE.sig"
        echo "Signed: $(cat "$OUT/$DMG_FILE.sig")"
    fi
    echo "Release files in $OUT/:"
    cat "$OUT/SHA256SUMS.txt"
    ;;
esac
