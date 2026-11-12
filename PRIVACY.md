# Privacy

NexoLLM's AI runs on your computer. This page says exactly what the app reads, what it keeps, where, and the
few cases in which it uses the network. The source code is public ([GPL-3.0](LICENSE)), so every line of this
page can be checked against what the app actually does.

## What runs on your computer

Everything that touches what you write: suggestions, alternatives and synonyms, the writing tools (improve,
grammar, formal, shorter, translate), Web Lookup summaries, screen reading (text recognition), your writing
style and memory, and — if you install it — the Audio Context plugin (Whisper speech recognition). None of it
uses a server. There is no account, no analytics and no crash reporting service.

## When the network is used

Only in these cases, each started by you or by a setting you control. Web Lookup (Settings → Engine → Behavior)
and the automatic update check (Settings → About) can each be turned off.

| When | What is sent | To |
|---|---|---|
| You download a model or the audio plugin | A standard file download request | Hugging Face |
| You press Web Lookup (`⌃⌥L`) | The highlighted text or your question, at most 300 characters | Wikipedia, Wiktionary, Wikiquote, DuckDuckGo's answer API, Google News |
| Once a day, if automatic update checks are on (the default) | A request for the latest release | GitHub |

All connections use HTTPS (TLS 1.2 or newer), without cookies or cache, and redirects can only lead to the
hosts listed above. Downloads are verified before they're used: models and the speech model by SHA-256, app
updates by an Ed25519 signature (see [SECURITY.md](SECURITY.md)).

## What it reads

| Source | When | Kept |
|---|---|---|
| Text around the cursor in the focused field | While you type, in apps where NexoLLM is active | In memory while you write |
| Short fields of the same window (subject, recipients, titles) | When you start writing in a field | In memory for that field |
| The window on screen | Only if Screen Recording is allowed: when you press `⌃⌥S`, or automatically at a few moments if you chose Smart | Turned into text on your computer, the image is dropped immediately. The text is kept in memory only |
| The clipboard | If "Use the clipboard" is on | In memory |
| Microphone and call audio | Only while the Audio Context plugin is installed **and** you turn listening on | Turned into text on your computer; audio is never saved and is overwritten in memory once transcribed. The transcript (about the last minute) is kept in memory only and erased when listening stops |

Password fields and apps that turn on secure input are never read, and neither are passwords copied from a
password manager.

## What it stores

Everything lives in your user account's local NexoLLM application data folder, restricted so only your user account can read it.

| File | Content | Protection |
|---|---|---|
| `history.bin` | What you wrote, used to learn your style (only in apps where recording is on) | AES-256-GCM, key in your system credential store |
| `memory.bin` | Short notes about recent topics, which fade over days | AES-256-GCM, same key |
| `stats.json` | Word counts per day and per app | Owner-only file |
| `Models/` | The language models you installed | |
| `Plugins/AudioContext/` | The speech model, only if you installed the plugin | |

You can turn recording off for any app and clear the history and the memory in Settings. Deleting the folder
removes everything.

## Audio Context

The plugin is optional, experimental and not installed with the app. Before it's downloaded you read a notice
about how it works and about recording other people, and agree to use it responsibly. Listening is
always off when NexoLLM starts, the status icon is shown while it's on (it can't be hidden), and it stops by
itself when the screen locks, the computer sleeps or after an hour without typing. Full text:
[LEGAL_AUDIO_PLUGIN.md](LEGAL_AUDIO_PLUGIN.md).

## Logs

A local `NexoLLM.log` file in your user logs folder holds technical events (model loaded, permissions). Detailed logging, which can
include short text fragments, is off unless you turn it on in Settings. The file is readable only by you. If
the app crashes, a report is shown on the next launch; it is never sent anywhere — you decide whether to copy
it into an issue.

## Questions

Open an issue at https://github.com/edevscomp/NexoLLM/issues
