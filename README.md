# Flowa

Voice dictation for macOS. Press `fn`, speak, press `fn` again — your words appear wherever your cursor is.

Runs entirely on your Mac. No subscription, no cloud, no data leaving your machine.

## How it works

1. Press `fn` — recording starts, a small floating bar appears
2. Speak for as long as you want (any language, mid-sentence switching is fine)
3. Press `fn` again — Flowa transcribes and pastes the text into whatever app you were using

That's it.

## Features

- **Fully local** — powered by Whisper Large v3 Turbo (CoreML), bundled inside the app. First dictation is instant, no download required
- **Any language** — 99 languages supported. Switch languages mid-session; Flowa picks it up automatically
- **Works everywhere** — dictates into any app: notes, email, chat, code editors, browsers
- **Menu bar icon** — stays running in the background, always ready
- **Recent history** — last 100 dictations saved locally, copyable from the Home screen
- **Launch at login** — optional, toggled from the app

## Requirements

- macOS 13 or later
- Apple Silicon (M1 or later) recommended — runs on Intel but model compilation takes longer on first launch

## Setup

1. Clone or download the repo
2. Open `Flowa.xcodeproj` in Xcode
3. Build and run (`⌘R`)
4. Grant the three permissions the app asks for:
   - **Microphone** — to capture your voice
   - **Input Monitoring** — to detect the `fn` key globally
   - **Accessibility** — to paste text into the focused app
5. Go to System Settings → Keyboard → set "Press 🌐 key to" → **Do Nothing** (otherwise macOS intercepts `fn` before Flowa sees it)

On first launch, the app compiles the Whisper model for your specific Mac. This takes ~2 minutes and only happens once.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Swift package, added via Xcode's package manager

## License

MIT — see [LICENSE](LICENSE)
