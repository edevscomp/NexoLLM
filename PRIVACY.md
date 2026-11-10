# Privacy

NexoLLM is built so that what you write never leaves your Mac. This page says exactly what it reads, what it
keeps and where.

## Network

With a local model, NexoLLM makes no network connections while you write: no analytics, no crash
reporting, no account. The model runs on your Mac's GPU.

These things use the network:

| When | What is sent | To |
|---|---|---|
| You download a model in Settings | A standard file download request | Hugging Face |
| You choose Cloud API and save a key | The text around the cursor, nearby fields and, if enabled, screen text, while you type | The provider you picked (OpenAI, Anthropic, Google or the URL you entered) |
| You use Smart Web Lookup (`⌃⌥L`) | The highlighted text or your question, at most 300 characters | Wikipedia, Wiktionary, Wikiquote, Google News and DuckDuckGo's answer API |
| Audio Context is on with High sensitivity (the default) | The room microphone's audio, to be transcribed | Apple's speech recognition service. Turn High sensitivity off to keep all audio on the Mac. Call audio stays on the Mac when the language's speech model is installed |
| Once a day, if "Check for updates" is on (the default) | A request for the latest release | GitHub |

API keys are stored in your Keychain and sent only to their provider, over HTTPS.

## What it reads

| Source | When | Kept |
|---|---|---|
| Text around the cursor in the focused field | While you type, in apps where NexoLLM is active | In memory while you write |
| Short fields of the same window (subject, recipients, titles) | When you start writing in a field | In memory for that field |
| The window on screen | Only if Screen Recording is allowed: when you press `⌃⌥S`, or automatically at a few moments if you chose Smart | Turned into text on the Mac, the image is dropped immediately. The text is kept in memory only |
| The clipboard | If "Use clipboard" is on | In memory |
| Microphone and call audio | Only while Audio Context is on (off by default; needs Microphone, Speech Recognition and, for calls, Screen Recording) | Turned into text, the audio is never saved. The transcript is kept in memory only |

Password fields and apps that turn on secure input are never read, and neither are passwords copied from a
password manager.

## What it stores

Everything lives in `~/Library/Application Support/NexoLLM`, a folder readable only by your macOS user.

| File | Content | Protection |
|---|---|---|
| `history.bin` | What you wrote, used to learn your style (only in apps where recording is on) | AES-256-GCM, key in your Keychain |
| `memory.bin` | Short notes about recent topics, which fade over days | AES-256-GCM, same key |
| `stats.json` | Word counts per day and per app | Owner-only file |
| `Models/` | The language model you installed | |

You can turn recording off for any app, clear the history and the memory in Settings, under Mind. Deleting
the folder removes everything.

## Logs

`~/Library/Logs/NexoLLM.log` holds technical events (model loaded, permissions). Detailed logging, which can
include short text fragments, is off unless you turn it on in Settings. The file is readable only by you.

## Questions

Open an issue at https://github.com/edevscomp/NexoLLM/issues
