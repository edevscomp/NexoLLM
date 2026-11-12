# Building NexoLLM

NexoLLM is a 100% local, on-device AI writing assistant powered by `llama.cpp` and `whisper.cpp`.

## 1. Native Desktop Build (Swift / App Bundle & Styled DMG)

```bash
git clone https://github.com/edevscomp/NexoLLM.git && cd NexoLLM
scripts/fetch-llama.sh       # llama.cpp framework into Vendor/, pinned and SHA-256 verified
scripts/fetch-whisper.sh     # whisper.cpp framework for the Audio Context plugin, same checks
./build.sh                   # builds release NexoLLM.app, stripped and signed
./build.sh install           # builds, installs and launches NexoLLM
./build.sh dist              # builds the custom-designed DMG installer, ZIP, SHA256SUMS and Ed25519 signatures
swift test                   # runs the automated unit test suite
```

## 2. Windows 10/11 & Linux Builds (Rust + Tauri v2 Workspace)

For Windows 10/11 (`x86_64` / `ARM64`) and Linux (`AppImage`, `.deb`, `.rpm`), see the complete cross-platform build instructions in [docs/MULTIPLATFORM.md](MULTIPLATFORM.md):

```powershell
# Windows 10/11 (PowerShell)
./platforms/scripts/build-windows.ps1
```

```bash
# Linux (Ubuntu / Debian / Fedora / Arch)
./platforms/scripts/build-linux.sh
```

```bash
# Cross-platform core unit tests
cd platforms && cargo test
```

## Releases (maintainer)

```bash
scripts/bump.sh minor        # or patch; writes VERSION and opens a CHANGELOG.md section
scripts/release.sh           # dist/ (styled DMG, ZIP, SHA256SUMS, signatures), public repository, GitHub release
```

Releases are signed with the maintainer's offline Ed25519 key (`scripts/release-signing.swift`); forks that publish
their own builds must generate their own key, put its public half in `Updater.publicKeyBase64`, and use a
different name and icon (see [TRADEMARKS.md](../TRADEMARKS.md)).

## Architecture

| Component | Role |
|---|---|
| `LLMEngine` / `nexollm-core` | Local `llama.cpp` GPU/CPU inference: KV-cache prefix reuse, cancellation, context-aware penalties, idle release |
| `CompletionController` | Keystrokes, inline ghost suggestions, Tab chaining, sessions, quick menu, 6-language writing tools, Web Lookup |
| `RewriteGuard` | Output guard before a rewrite replaces your text (no echoed examples, no runaway answers) |
| `Accessibility` | Focused text and caret coordinates around the cursor across desktop apps |
| `SuggestionText` | Prompt and cleanup logic: context header, fact copying, punctuation, insertion safety |
| `ScreenContext` | Event-driven or manual screen OCR, text only, kept in volatile memory |
| `AudioContext` | Optional Audio Context plugin: far-field gain, phrase segmentation, consent and model management |
| `WhisperEngine` | Local `whisper.cpp` on-device speech-to-text across 6 active languages (`EN`, `IT`, `ES`, `FR`, `DE`, `PT`) |
| `Memory`, `Style`, `History` | AES-256-GCM encrypted memory, per-app style profile, encrypted typing history |
| `GhostOverlay` | Ghost text, alternatives list, toasts, Web Lookup card and screen region selector |
| `ModelManager` | Hardware profile detection, model catalog, SHA-256 verified downloads, GGUF import and deletion |
| `Updater` | Offline Ed25519 + SHA-256 signed update verification with anti-downgrade protection |
| `SecureNet` | HTTPS-only sessions, TLS 1.2+, host-restricted redirects |
| `SystemTextPrefs` | Reversible switches for system inline predictions and autocorrect |
| `UI/` & `platforms/ui/` | Aurora/Glass Settings window, soft pastel stacked Insights histogram, and interactive 9-slide Tour |

## Contributing

Open an issue first for anything bigger than a fix. Keep changes focused, add a test where it makes sense,
and run the test suite before opening a pull request. By contributing you agree that your contribution is
licensed under the GPL-3.0.
