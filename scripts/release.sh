#!/bin/bash
# Publishes NexoLLM: the source code (GPL-3.0) to the public repository and the signed macOS build as a GitHub release.
#   scripts/release.sh source     update the public repository with the current source (no build, no release)
#   scripts/release.sh            build + sign dist/, update the public repository, create the GitHub release,
#                                 then update the Homebrew cask (brew install --cask edevscomp/nexollm/nexollm)
#   scripts/release.sh tap        republish only the Homebrew cask for the current VERSION and dist/ build
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLIC_REPO="${PUBLIC_REPO:-edevscomp/NexoLLM}"
PUBLIC_REMOTE="${PUBLIC_REMOTE:-https://github.com/$PUBLIC_REPO.git}"
VERSION="$(tr -d '[:space:]' < VERSION)"
WORK=".showcase-repo"
TAP_REPO="${TAP_REPO:-edevscomp/homebrew-nexollm}"
TAP=".tap-repo"
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
            -m "Co-authored-by: Claude <noreply@anthropic.com>"
        echo "Committed source snapshot for $VERSION."
    fi
    git -C "$WORK" push --quiet -u origin main
    echo "Pushed to $PUBLIC_REMOTE"
}

# Homebrew cask in its own tap repository. Version and SHA-256 come from the signed dist/ build.
publish_tap() {
    local sha
    sha="$(awk '/NexoLLM-macos.dmg/ {print $1}' dist/SHA256SUMS.txt)"
    [[ -n "$sha" ]] || { echo "dist/SHA256SUMS.txt has no DMG checksum: run ./build.sh dist first." >&2; exit 1; }
    if [[ ! -d "$TAP/.git" ]]; then
        rm -rf "$TAP"
        git clone --quiet "https://github.com/$TAP_REPO.git" "$TAP"
    fi
    git -C "$TAP" pull --quiet --ff-only origin main 2>/dev/null || true
    mkdir -p "$TAP/Casks"
    cat > "$TAP/Casks/nexollm.rb" <<CASK
cask "nexollm" do
  version "$VERSION"
  sha256 "$sha"

  url "https://github.com/$PUBLIC_REPO/releases/download/v#{version}/NexoLLM-macos.dmg"
  name "NexoLLM"
  desc "On-device inline autocomplete and writing tools for every app"
  homepage "https://github.com/$PUBLIC_REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "NexoLLM.app"

  zap trash: [
    "~/Library/Application Support/NexoLLM",
    "~/Library/Caches/com.edevs.NexoLLM",
    "~/Library/HTTPStorages/com.edevs.NexoLLM",
    "~/Library/Logs/NexoLLM*.log",
    "~/Library/Preferences/com.edevs.NexoLLM.plist",
  ]

  caveats <<~EOS
    NexoLLM is not notarized yet, so the first launch is blocked by Gatekeeper:
    open System Settings › Privacy & Security and click "Open Anyway" once.
    Then grant Accessibility access when NexoLLM asks for it.
  EOS
end
CASK
    git -C "$TAP" add -A
    if git -C "$TAP" diff --cached --quiet; then
        echo "Homebrew cask already up to date."
    else
        git -C "$TAP" -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
            commit --quiet -m "nexollm $VERSION"
        git -C "$TAP" push --quiet origin HEAD:main
        echo "Homebrew cask updated to $VERSION ($TAP_REPO)"
    fi
}

release_notes() {
    cat <<EOF
### Download

- **Installer (\`.dmg\`):** [**NexoLLM-macos.dmg**](https://github.com/$PUBLIC_REPO/releases/download/v$VERSION/NexoLLM-macos.dmg)
- **Homebrew:** \`brew install --cask edevscomp/nexollm/nexollm\`
- **Windows & Linux:** *Work in progress (currently in active development).*

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
tap)
    publish_tap
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
    publish_tap
    ;;
*)
    echo "usage: $0 [source|tap]" >&2; exit 1 ;;
esac
