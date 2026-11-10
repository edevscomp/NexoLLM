# Changelog

Every release of NexoLLM, newest first. Versions follow [Semantic Versioning](https://semver.org).
NexoLLM is in beta: until 1.0 a minor version (0.x.0) can change behavior, a patch (0.x.y) only fixes things.
The build number in parentheses grows with every commit.

## [Unreleased]

### Audio Context
Listens to the room and to call audio (Zoom, Meet, Teams, browser videos) and uses what's said as context.
A high-pass filter, consonant pre-emphasis and automatic gain pick up a voice two meters away in an echoey
room. **Auto** switches between Italian and English on its own when the speaker changes language. High
sensitivity (Apple's speech service, on by default) can be turned off to keep all audio on the Mac. ⌃⌥M →
Audio Context starts/stops listening and picks the language; Mind → Awareness shows a live transcript.

### Smart Web Lookup (⌃⌥L)
Highlighted text anywhere is looked up at once; with nothing highlighted, a search bar opens (drag on screen
to read an area). Typos are fixed before searching, sources follow the language you search in, idioms get
their figurative meaning (built-in dictionary + Wikiquote usage examples) and questions get the latest news
with a quick summary. The card has a Copy button.

### Writing tools
Improve, Fix Grammar, Make Formal, Make Shorter and Translate use the whole paragraph, keep your language
(even for a single word like "xciao" → "ciao" with the app in English) and never mix English into Italian.
A rewrite is cancelled if the text changes while it's being written.

### Whole-screen context
⌃⌥S reads every window on screen and keeps the parts that match what you're writing; Awareness shows what
was read.

### Security
Passwords copied from password managers are never read. Paste-based insertion restores the whole clipboard
(images and files included) and is hidden from clipboard history apps. Lookup cards open only web links,
at most 300 characters of selected text are sent to search engines, and updates download only over HTTPS
from GitHub.

### Fixes
The model freed after inactivity reloads on demand for lookups, rewrites, alternatives and synonyms.
Closing the lookup bar no longer cancels the answer. The quick menu opens at the caret in a text field and
at the mouse elsewhere, with arrow-key navigation and hover highlight.

## [0.6.0] - 2026-11-03

### Rewrite selected text
Select a sentence anywhere and press ⌃⌥M: Improve Writing, Fix Grammar, Make Formal, Make Shorter and
Translate IT ⇄ EN replace it in place. Best with a cloud provider; the local model works as a fallback.

### Privacy Inspector
Mind → Awareness shows exactly what NexoLLM holds in memory right now: the text read from the screen,
nearby window fields and the clipboard, with Clear Now. While the screen is being read, the menu bar
icon turns into a viewfinder.

### Playground
Overview has a box to try NexoLLM right away: Tab, the full-suggestion key, alternatives and the menu all
work there, and nothing typed in it is saved.

### Look and sound
Optional: a quiet tap when you accept, suggestions tinted with the accent color, and suggestion opacity.
All off by default (Engine → Behavior).

### Fixes
Suggestions could turn invisible while Tab still accepted them; they now always stay opaque. ⌥Tab and
⌃⌥M no longer get stuck after a cancelled request, and ⌃⌥M also works with NexoLLM's window in front.
⌘Q, ⌘W, copy and paste work in NexoLLM's window, which now shows its menu bar while open. Every picker
and dropdown uses the same outlined style as the buttons.

### Releases
Public builds are signed with a Developer ID certificate and notarized by Apple when one is set up.

## [0.5.0] - 2026-11-03

### Alternatives and synonyms
The list opens the moment you press the key and fills in as soon as the results are ready. ← and →
switch between Word and Phrase; switching back is instant. Alternatives now look only at what you're
writing, so labels like "Draft" or app names no longer show up in the list.

### Suggestions
Nothing is suggested on top of an empty field's placeholder. When there's no room after the cursor, the
suggestion appears below the line instead of disappearing.

### Cloud API
A key is checked before it's kept. A key the provider refuses is removed, and NexoLLM keeps using the
model on your Mac until a key works.

### Interface
New outlined buttons and switches that light up when you point at them or reach them with the
keyboard. The ⌃⌥M menu shows what NexoLLM is doing on its own line, and "Open NexoLLM" replaces
"Settings". Insights shows words written, suggestions accepted, time saved and your top apps.
Memory & Style has a Clear Cache button.

## [0.4.0] - 2026-11-02

### Lists
Use ↑ and ↓ to move through alternatives, synonyms and emoji, then Return or Tab to insert. Numbers and
clicks still work.

### Quick menu
⌃⌥M opens a new menu at the cursor. Move with the arrow keys, press a number or click. Escape closes it.

### Models
Five more models to download: Qwen 2.5 7B, Mistral 7B, Qwen 2.5 3B, SmolLM2 1.7B and Llama 3.2 1B. They
are listed in one menu instead of a long list. Cloud models are picked from a menu, and a key is checked
as soon as you save it.

### Privacy
Text with a password, API key, card number or IBAN is never saved. The encryption key is cleared from
memory when the screen locks. Logs no longer contain anything you type. About → Privacy explains what
NexoLLM stores and where it connects.

### About
Report a Bug and What's New now open inside the app. NexoLLM checks GitHub once a day for a new version
(you can turn this off) and downloads it for you.

## [0.3.0] - 2026-10-30

### Better suggestions
Suggestions now start from the half-typed word instead of after it. Before, the model could only add
letters to what you had typed, so the obvious word was often out of reach and a rare, longer one came up
instead. The word you're typing also keeps its capitalization.

Spelling corrections follow the language of the sentence, use the sentence for context and only fix near
misses: one or two letters off, swapped letters or a missing accent. Names, acronyms and words you use
often are never corrected. Suggestions are no longer held back while a word is only half typed.

### Alternatives
⌥Tab lists other words for the one you're typing, or for the next one, at any point. Press it again to
switch to other ways of finishing the sentence. With a word selected it lists synonyms.

### Models
NexoLLM detects your Mac's chip and memory and recommends a model for when you're plugged in and one for
battery. Models can be downloaded from Settings (verified with SHA-256), imported from a GGUF file or
deleted to free the space. Bring your own key for OpenAI, Anthropic, Google Gemini or any
OpenAI-compatible service to use a cloud model instead; keys are stored in the Keychain.

### Interface
The floating button is gone. The menu bar icon shows the status, ⌃⌥M opens the menu at the cursor and a
short note confirms when you pause or resume. Setting descriptions moved into an ⓘ popover, texts are
shorter, and the app is English throughout, numbers and dates included. Light and dark appearance can
be chosen in Behavior. The About page has links to GitHub, bug reports and release notes. Saved texts
can be browsed, searched and deleted one by one, with their real size on disk.

## [0.2.0] - 2026-10-27

The first release under the NexoLLM name.

### Suggestions
Ghost text now finds the caret reliably in apps that report a wrong box for an empty selection (Safari,
Mail, Electron apps): every position is cross-checked with the character before the caret and with the
field, so the suggestion no longer jumps to a corner of the window.

A new suggestion appears with a tiny 120 ms fade and a 2 pt drift. Text that shrinks while you type or
accept it doesn't animate again. Reduce Motion turns the effect off.

### Interface
The floating button has a fixed home: inside the right end of a one-line field, in the bottom-right
corner of a larger one (top-right while you're typing down there). It hides on whole-page canvases and
never floats away from the field.

The menu bar and button menus are the same short menu: status, the app in front, a Pause submenu,
Read the Screen Now, Settings.

Settings pages switch with a short fade, and the tab pill slides to the selected section.

### Privacy and security
The data folder is readable only by your user (0700, files 0600), stored files are size-checked before
they're read, and inserted text is stripped of control and bidi-override characters.
The encryption key is read once per launch and kept in memory.

### Distribution
Builds are compiled without debug info, stripped and signed with the hardened runtime.
`./build.sh dist` produces the DMG and ZIP for GitHub Releases with their SHA-256 checksums.
llama.cpp downloads are verified against a pinned checksum.

### Fixed
CI failed on Swift 6.0 (`weak let` in ScreenContext).

## [0.1.0] - 2026-10-26

First preview.

Completions in any app, at the end of a line or inside text, accepted word by word (`Tab`) or whole.
Punctuation always takes its own `Tab`, so you decide where a sentence stops. Smart Tab keeps indenting
after list markers. Autocorrect bubbles, emoji (`:word`), alternatives and synonyms on demand.

Context from the other fields of the window (subject, recipients, titles) with exact facts copied from
them, optional screen reading (smart or only on `⌃⌥S`), an episodic memory of recent topics and a writing
style profile learned per app.

Works with Pages, Keynote and Numbers, adapts the ghost text color to the page under the cursor, uses 0%
CPU when idle and switches to a smaller model on battery.
