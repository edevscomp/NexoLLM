# Security

NexoLLM reads text through macOS Accessibility and types on your behalf, so security reports are taken
seriously and answered first.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead:
**Security → Report a vulnerability** on https://github.com/edevscomp/NexoLLM/security/advisories/new

Include the NexoLLM version (Settings → About), your macOS version and the steps to reproduce.
You'll get an answer within a few days.

## Supported versions

Only the latest beta receives fixes.

## Verifying a download

Every release lists the SHA-256 of its files in `SHA256SUMS.txt`. Check yours with:

```bash
shasum -a 256 NexoLLM-*.dmg
```

## How the app protects you

In local mode the app makes no network connections. Downloaded models are verified against their SHA-256,
cloud API keys live in the Keychain and travel only over HTTPS to their provider. History and memory are
encrypted (AES-256-GCM, key in the Keychain) in an owner-only folder, password fields and secure input are
never read, and the app is signed with the hardened runtime, which blocks code injection.
