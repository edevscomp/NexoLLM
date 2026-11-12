#!/bin/bash
# Bumps the semantic version in VERSION and opens a new section in CHANGELOG.md.
#   scripts/bump.sh patch   # 0.2.0 -> 0.2.1  (fixes)
#   scripts/bump.sh minor   # 0.2.1 -> 0.3.0  (new features or changed behavior, while in beta)
#   scripts/bump.sh major   # 0.9.0 -> 1.0.0  (the first stable release, later breaking changes)
# The build number (CFBundleVersion) is automatic: it grows with every commit (set by build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

part="${1:-patch}"
IFS=. read -r major minor patch < VERSION
case "$part" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac
new="$major.$minor.$patch"
echo "$new" > VERSION

today="$(date +%Y-%m-%d)"
if ! grep -q "^## \[$new\]" CHANGELOG.md; then
    tmp="$(mktemp)"
    awk -v v="$new" -v d="$today" '
        !done && /^## \[/ { print "## [" v "] - " d "\n\nDescribe what changed.\n"; done = 1 }
        { print }
    ' CHANGELOG.md > "$tmp" && mv "$tmp" CHANGELOG.md
fi
echo "Version $new. Describe the changes in CHANGELOG.md, then commit."
