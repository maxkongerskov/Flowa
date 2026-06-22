# Flowa

Voice dictation for macOS. Press `fn`, speak, press `fn` again — your words appear wherever your cursor is.

Runs entirely on your Mac. No subscription, no cloud, no data leaving your machine.

## How it works

1. Press `fn` — recording starts, a small floating bar appears
2. Speak for as long as you want (any language, mid-sentence switching is fine)
3. Press `fn` again — Flowa transcribes and pastes the text into whatever app you were using

That's it.

## Features

- **Fully local** — powered by Whisper Large v3 Turbo (CoreML). The model (~1.5 GB) downloads once on first launch; after that everything runs on your Mac with no network
- **Any language** — 99 languages supported. Switch languages mid-session; Flowa picks it up automatically
- **Works everywhere** — dictates into any app: notes, email, chat, code editors, browsers
- **Menu bar icon** — stays running in the background, always ready
- **Recent history** — last 100 dictations saved locally, copyable from the Home screen
- **Launch at login** — optional, toggled from the app

## Requirements

- macOS 14 or later
- Apple Silicon (M1 or later) recommended — runs on Intel but model compilation takes longer on first launch
- An internet connection on first launch only (to download the ~1.5 GB speech model)

## Setup

1. Clone or download the repo
2. Open `Flowa.xcodeproj` in Xcode
3. Build and run (`⌘R`)
4. Grant the three permissions the app asks for:
   - **Microphone** — to capture your voice
   - **Input Monitoring** — to detect the `fn` key globally
   - **Accessibility** — to paste text into the focused app
5. Go to System Settings → Keyboard → set "Press 🌐 key to" → **Do Nothing** (otherwise macOS intercepts `fn` before Flowa sees it)

On first launch, Flowa downloads the Whisper model (~1.5 GB) and then compiles it for your specific Mac. This needs an internet connection, happens once, and shows a progress screen — you reach the main window only after it finishes. Every launch after that is offline.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Swift package, added via Xcode's package manager

## License

MIT — see [LICENSE](LICENSE)
