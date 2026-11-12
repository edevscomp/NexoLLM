# NexoLLM Multiplatform Architecture (Windows 10/11, Linux & macOS)

NexoLLM is designed around a strict **100% on-device AI, zero-telemetry, device-neutral** core. Every suggestion, writing tool rewrite, translation, summary, screen OCR pass, and room/call speech transcription runs locally on the user's own hardware (`llama.cpp` + `whisper.cpp`).

This document describes the cross-platform workspace under [`platforms/`](../platforms/) for **Windows 10/11** and **Linux (X11 & Wayland)** alongside the native Swift/AppKit target in [`Sources/NexoLLM/`](../Sources/NexoLLM/).

---

## 1. Repository Layout

```text
platforms/
├── Cargo.toml                  # Shared Rust workspace (core, windows, linux, ui/src-tauri)
├── core/                       # nexollm-core: OS-independent engine, security, stats & 6-language i18n
│   └── src/
│       ├── lib.rs
│       ├── engine.rs           # llama.cpp GGUF + whisper.cpp 6-lang STT + AmbientGain DSP + SpeechSegmenter
│       ├── crypto_store.rs     # AES-256-GCM encrypted history.bin & memory.bin + RAM key zeroization
│       ├── rewrite_guard.rs    # Anti-leak prompt guard, 6-lang RewriteExamples & Spelling detector
│       ├── stats.rs            # Per-app daily word stats, soft pastel AppPalette & StackedBucket
│       ├── updater.rs          # Offline Ed25519 release verification, anti-downgrade & TLS 1.3 allowlists
│       └── i18n.rs             # 6 active languages (EN, IT, ES, FR, DE, PT), TourExamples & universal notices
├── windows/                    # nexollm-windows: native Win32 / UIAutomation / WASAPI / DPAPI adapter
├── linux/                      # nexollm-linux: native AT-SPI2 / IBus (Wayland+X11) / PipeWire / libsecret adapter
├── ui/                         # Shared Aurora/Glass desktop UI (Tauri v2 + TypeScript + CSS)
│   ├── index.html
│   ├── src/styles.css
│   ├── src/app.ts              # Stacked pastel histogram + fade tooltip, 6-lang UI & wrapping 9-slide Tour
│   └── src-tauri/              # Local IPC bridge to nexollm-core + platform adapter
└── scripts/
    ├── build-windows.ps1       # Builds .msi / .exe installer + Ed25519 .sig
    └── build-linux.sh          # Builds .deb / .rpm / .AppImage + IBus component + Ed25519 .sig
```

---

## 2. Feature & OS Integration Matrix

| Capability | Windows 10 / 11 (`nexollm-windows`) | Linux X11 (`nexollm-linux`) | Linux Wayland (`nexollm-linux`) |
|---|---|---|---|
| **Local LLM (`llama.cpp`)** | Vulkan / CUDA / DirectML / AVX2 | Vulkan / CUDA / ROCm / AVX2 | Vulkan / CUDA / ROCm / AVX2 |
| **Local Speech (`whisper.cpp`)** | 6 languages (`EN`, `IT`, `ES`, `FR`, `DE`, `PT`) + Auto | 6 languages (`EN`, `IT`, `ES`, `FR`, `DE`, `PT`) + Auto | 6 languages (`EN`, `IT`, `ES`, `FR`, `DE`, `PT`) + Auto |
| **Caret & Text Context** | `UIAutomation` (`IUIAutomationTextPattern2` + `ValuePattern`) | `AT-SPI2` (`org.a11y.atspi.Text`) + `IBus` | Native `IBus` Input Method (`nexollm-ibus`) + `AT-SPI2` |
| **Password Field Blocking** | `UIA_IsPasswordPropertyId` + credential class filter | `ATSPI_ROLE_PASSWORD_TEXT` + `STATE_SENSITIVE` | `IBusInputPurpose::Password` / `Pin` + `AT-SPI2` |
| **Key Interception & Insertion** | `WH_KEYBOARD_LL` + `SendInput` (`KEYEVENTF_UNICODE`) | `IBus` / `XInput2` + `XTest` | `IBusEngine::process_key_event` + `commit_text` |
| **Ghost Overlay & Quick Menu** | `WS_EX_LAYERED \| WS_EX_NOACTIVATE \| WS_EX_TOPMOST` | GTK4 / X11 ARGB composited popup | `IBus` preedit / candidate popup + `gtk4-layer-shell` |
| **Screen Context (OCR)** | `Windows.Graphics.Capture` + `Windows.Media.Ocr` | XShm / Portal + local `Tesseract` (6 langs) | `xdg-desktop-portal` (`ScreenCast` session token) + `Tesseract` |
| **Room & Call Audio Capture** | `WASAPI` Mic + `AUDCLNT_STREAMFLAGS_LOOPBACK` | `PipeWire` Mic + Sink `.monitor` | `PipeWire` Mic + Sink `.monitor` |
| **Encrypted Store Key** | Windows `DPAPI` (`CryptProtectData` per-user) | `libsecret` (`org.freedesktop.secrets`) | `libsecret` (`org.freedesktop.secrets`) |
| **Lock / Sleep Auto-Wipe** | `WTS_SESSION_LOCK` + `PBT_APMSUSPEND` | `org.freedesktop.login1` (`Lock` / `PrepareForSleep`) | `org.freedesktop.login1` (`Lock` / `PrepareForSleep`) |
| **System Tray Safeguard** | `Shell_NotifyIconW` (locked visible while listening) | `StatusNotifierItem` (locked visible while listening) | `StatusNotifierItem` (locked visible while listening) |

### Transparent Note on Linux Wayland
By design, Wayland compositors isolate client windows from reading global keystrokes or positioning arbitrary unmanaged popups at another window's cursor coordinates. NexoLLM solves this cleanly without weakening system security:
1. **`nexollm-ibus` Input Method Engine**: registers as a standard IBus input method component (`set_capabilities(IBUS_CAP_SURROUNDING_TEXT | IBUS_CAP_PREEDIT_TEXT)`). Wayland and X11 applications natively supply surrounding text, exact cursor rectangles (`set_cursor_location`), and key events (`Tab`, `Shift+Tab`, `Alt+Tab`, `Esc`) directly to NexoLLM, while password fields report `IBUS_INPUT_PURPOSE_PASSWORD` and are ignored before a single character is read.
2. **Screen Context via `xdg-desktop-portal`**: uses `org.freedesktop.portal.ScreenCast` with a user-approved restore token so screenshots are decoded in memory by local Tesseract OCR and discarded immediately.

---

## 3. Shared Security & Privacy Guarantees

1. **100% On-Device Inference**: no cloud API keys or external inference endpoints exist in any target.
2. **Offline Ed25519 Release Verification**: every installer (`.dmg`, `.msi`, `.exe`, `.AppImage`, `.deb`, `.rpm`) is verified offline against the embedded Ed25519 public key (`AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo=`) over `NexoLLM-release-v1:<version>:<sha256>` with strict semantic anti-downgrade enforcement before opening.
3. **SHA-256 Verified Weights**: GGUF language models and Whisper speech models downloaded from Hugging Face over HTTPS (TLS 1.3) are verified against their pinned SHA-256 digests prior to loading.
4. **Zero-Persistence Audio & Screen Context**: raw audio frames pass through `AmbientGain` and `SpeechSegmenter` in RAM only and are overwritten with zeros (`zeroize`) immediately upon transcription, stop, screen lock, system sleep, or 60 minutes of typing inactivity.
5. **Jurisdiction-Neutral Audio Consent (`v2`)**: the Audio Context plugin is never bundled by default, never starts automatically at launch, requires explicit acceptance of the universal privacy/consent notice, and keeps the tray/status indicator visible whenever active.

---

## 4. Building & Testing

### Shared Core Tests
```bash
cd platforms
cargo test -p nexollm-core
```

### Windows 10/11 (x64 & ARM64)
Prerequisites: Rust stable (`msvc`), Visual Studio Build Tools 2022 (C++ + Windows 11 SDK), CMake, Node.js 20+.
```powershell
pwsh platforms/scripts/build-windows.ps1 -Configuration Release
```

### Linux (Debian/Ubuntu, Fedora, Arch — X11 & Wayland)
Prerequisites: Rust stable, `cmake`, `pkg-config`, `libibus-1.0-dev`, `libatspi2.0-dev`, `libpipewire-0.3-dev`, `libsecret-1-dev`, `libwebkit2gtk-4.1-dev`, `tesseract-ocr`, Node.js 20+.
```bash
./platforms/scripts/build-linux.sh --release
```
