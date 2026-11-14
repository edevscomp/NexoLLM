# Audio Context plugin — notice

*Applies to NexoLLM 0.9.0 and later. Notice version 2.*

Audio Context is an **optional, experimental** NexoLLM plugin. It turns speech from the microphone (a lecture,
a meeting) and, when screen and audio capture is allowed, from calls and videos playing on the computer into
text, and uses that text as context for writing suggestions. It is not part of the app: it is downloaded only
after you read this notice and agree to it in Settings → Mind → Awareness.

## 1. How it works

- **On this computer only.** Speech is recognized by Whisper (whisper.cpp, MIT License) running on your
  computer. No audio and no transcript is sent to NexoLLM or to anyone else. The plugin works without an
  internet connection.
- **Audio is never stored.** Audio stays in memory only until it is transcribed (a few seconds) and is then
  overwritten with zeros. It is never written to disk.
- **The transcript is temporary.** About the last minute of text is kept in memory only, to give context to
  suggestions. It is erased when listening stops, when the screen locks and when the computer sleeps.
- **The only download** is the speech model itself (from Hugging Face, verified by SHA-256). Removing the
  plugin deletes it and withdraws your consent.
- **Languages.** English, Italian, Spanish, French, German and Portuguese, detected automatically or chosen
  by you.

## 2. Built-in safeguards

- Listening is **always off** when NexoLLM starts: it never resumes by itself.
- While listening, the NexoLLM status icon is **always shown** (it can't be hidden), next to the operating
  system's own microphone indicator.
- Listening **stops by itself** when the screen locks, when the computer sleeps, and after 10 minutes without
  typing.
- You can see the live transcript and clear it at any time (Settings → Mind → Awareness, Privacy Inspector).

## 3. Your responsibility

Recording or transcribing other people's voices may be subject to privacy and consent rules, which differ
from place to place and from situation to situation (for example, schools, universities and workplaces often
have their own policies).

By installing the plugin you agree to use it **only**:

1. for **your own voice**; or
2. for **public content** (public talks, broadcasts, videos you are allowed to watch); or
3. when the **people speaking are informed and agree**, or when you have an **appropriate authorization**
   (for example from your school or university, an accessibility accommodation, or your employer's policy);

and **never** to capture conversations covertly, or conversations you are not part of.

This notice is general information, not legal advice. If you are unsure whether a use is appropriate, ask the
people involved first, or don't use the plugin in that situation.

## 4. No warranty

The plugin is experimental and provided "as is", without warranty of any kind, as stated in the
[GNU General Public License v3.0](LICENSE). Transcriptions can contain mistakes; don't rely on them for
anything important.

## 5. Your consent

In the app you confirm two statements before anything is downloaded:

- *I understand that audio is processed only on this computer, never saved and never sent.*
- *I will use it only for my own voice, for public content, or when the people speaking are informed and
  agree.*

You can read this notice again and remove the plugin at any time from Settings → Mind → Awareness.
