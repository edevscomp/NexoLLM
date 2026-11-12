#!/bin/bash
# Publishes NexoLLM: the source code (GPL-3.0) to the public repository and the signed build as a GitHub release.
#   scripts/release.sh source     update the public repository with the current source (no build, no release)
#   scripts/release.sh            build + sign dist/, update the public repository, create the GitHub release
#
# When the GitHub release is published, `.github/workflows/release.yml` automatically builds and attaches the
# native Windows (.exe) and Linux (.AppImage, .deb) installers and updates SHA256SUMS.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_REPO="${PUBLIC_REPO:-edevscomp/NexoLLM}"
PUBLIC_REMOTE="${PUBLIC_REMOTE:-https://github.com/$PUBLIC_REPO.git}"
VERSION="$(tr -d '[:space:]' < VERSION)"
WORK=".showcase-repo"
PRIVATE=(docs/dev)

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first: the snapshot is taken from HEAD." >&2; exit 1; }

publish_source() {
    if [[ ! -d "$WORK/.git" ]]; then
        rm -rf "$WORK"
        git clone --quiet "$PUBLIC_REMOTE" "$WORK" 2>/dev/null || { git init --quiet -b main "$WORK"; git -C "$WORK" remote add origin "$PUBLIC_REMOTE"; }
    fi
    git -C "$WORK" pull --quiet --ff-only origin main 2>/dev/null || true
    find "$WORK" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
    git archive HEAD | tar -x -C "$WORK"
    for p in "${PRIVATE[@]}"; do rm -rf "${WORK:?}/$p"; done
    if grep -rIl --exclude-dir=.git --exclude=WritingQualityTests.swift -E "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|NexoLLM Release Signing.*-w [A-Za-z0-9+/]{40}" "$WORK" >/dev/null; then
        echo "Refusing to publish: something that looks like a private key is in the snapshot." >&2; exit 1
    fi
    git -C "$WORK" add -A
    if git -C "$WORK" diff --cached --quiet; then
        echo "Public repository already up to date."
    else
        git -C "$WORK" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
            commit --quiet -m "NexoLLM $VERSION" \
            -m "Co-authored-by: Claude <noreply@anthropic.com>" \
            -m "Co-authored-by: Gemini <gemini@google.com>"
        echo "Committed source snapshot for $VERSION."
    fi
    git -C "$WORK" push --quiet -u origin main
    echo "Pushed to $PUBLIC_REMOTE"
}

release_notes() {
    cat <<EOF
### Downloads

| Operating System | Installer |
| :--- | :--- |
| **Windows 10 / 11 (64-bit)** | [**NexoLLM-windows-x64-setup.exe**](https://github.com/$PUBLIC_REPO/releases/download/v$VERSION/NexoLLM-windows-x64-setup.exe) |
| **Linux (64-bit AppImage)** | [**NexoLLM-linux-x86_64.AppImage**](https://github.com/$PUBLIC_REPO/releases/download/v$VERSION/NexoLLM-linux-x86_64.AppImage) |
| **Linux (Debian / Ubuntu .deb)** | [**NexoLLM-linux-amd64.deb**](https://github.com/$PUBLIC_REPO/releases/download/v$VERSION/NexoLLM-linux-amd64.deb) |
| **macOS (64-bit .dmg)** | [**NexoLLM-macos.dmg**](https://github.com/$PUBLIC_REPO/releases/download/v$VERSION/NexoLLM-macos.dmg) |

---

EOF
    awk -v v="$VERSION" '
        $0 ~ "^## \\[" v "\\]" { on = 1; next }
        on && /^## \[/ { exit }
        on { print }
    ' CHANGELOG.md
}

case "${1:-all}" in
source)
    publish_source
    ;;
all)
    ./build.sh dist
    publish_source
    command -v gh >/dev/null || { echo "Install the GitHub CLI to create the release: brew install gh && gh auth login" >&2; exit 1; }
    notes="$(mktemp)"; release_notes > "$notes"
    gh release create "v$VERSION" \
        dist/NexoLLM-macos.dmg \
        dist/NexoLLM-macos.dmg.sig \
        dist/SHA256SUMS.txt \
        --repo "$PUBLIC_REPO" --title "NexoLLM $VERSION" --notes-file "$notes" --latest
    rm -f "$notes"
    git tag -f "v$VERSION" >/dev/null
    echo "Released NexoLLM $VERSION on https://github.com/$PUBLIC_REPO/releases"
    ;;
*)
    echo "usage: $0 [source]" >&2; exit 1 ;;
esac
