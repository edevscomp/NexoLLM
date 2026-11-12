# Security

NexoLLM reads text through system accessibility APIs and types on your behalf, so security reports are taken
seriously and answered first.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on https://github.com/edevscomp/NexoLLM/security/advisories/new

Include the NexoLLM version (Settings → About), your operating system version and the steps to reproduce.
You'll get an answer within a few days.

## Supported versions

Only the latest release receives fixes.

## Signed updates

Every release since 0.8.0 is signed with an **Ed25519** key held offline by the maintainer. The signature
covers the exact message

```
NexoLLM-release-v1:<version>:<sha256 of release installer>
```

and is published next to each release installer as `<installer>.sig` (for example `NexoLLM-macos.dmg.sig`). The public key is compiled into the app:

```
AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo=
```

Before opening a downloaded update, the app recomputes the SHA-256 of the file, checks that the version is
newer than the installed one and verifies the signature. If anything doesn't match — a file modified in
transit, a file replaced on the server, an older release presented as new — the download is deleted and
nothing is opened. Because the private key never leaves the maintainer's computer, this holds even if the
network or the GitHub account were compromised.

Network requests use HTTPS with TLS 1.2 or newer, no cookies and no cache; redirects are allowed only to the
expected hosts (GitHub for updates, Hugging Face for models, the listed services for Web Lookup).

## Verifying a download by hand

```bash
# Compare the SHA-256 hash with SHA256SUMS.txt in the release:
shasum -a 256 <installer-file>        # or: sha256sum <installer-file>
                                      # or PowerShell: Get-FileHash <installer-file> -Algorithm SHA256
```

To check the Ed25519 signature yourself, verify `NexoLLM-release-v1:<version>:<sha256>` against the `.sig` file using the public key above (`AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo=`).

## Building it yourself

The source is public under the GPL-3.0: you can read it and build the app yourself with
[docs/BUILDING.md](docs/BUILDING.md). The binary AI runtimes (llama.cpp and whisper.cpp) are pinned to a
release and verified by SHA-256 before use.

## How the app protects you

- The AI runs on your computer; nothing you write is sent to an AI service.
- Downloaded models and the speech model are verified against their SHA-256.
- History and memory are encrypted (AES-256-GCM, key stored in your system credential store) in an owner-only
  folder; the key is dropped from memory when the screen locks.
- Password fields, secure input and password-manager copies are never read; text containing passwords, API
  keys, card numbers or IBANs is never saved.
- Official builds enable runtime library-injection protections.
- Audio Context never starts by itself, is always visible in the system tray / menu bar while on, and stops on lock/sleep.
