# Flowa

Voice dictation for macOS. Press `fn`, speak, press `fn` again — your words appear wherever your cursor is.

Runs entirely on your Mac. No subscription, no cloud, no data leaving your machine.

## How it works

1. Press `fn` — recording starts, a small floating bar appears
2. Speak for as long as you want (any language, mid-sentence switching is fine)
3. Press `fn` again — Flowa transcribes and pastes the text into whatever app you were using

That's it.

## Features

- **Fully local** — speech engine is **bundled** in the app (~1.5 GB). No download. First launch only prepares it for this Mac (~2 minutes, offline)
- **Any language** — 99 languages supported. Switch languages mid-session; Flowa picks it up automatically
- **Works everywhere** — dictates into any app: notes, email, chat, code editors, browsers
- **Menu bar icon** — stays running in the background, always ready
- **Recent history** — last 100 dictations saved locally, copyable from the Home screen
- **Launch at login** — optional, toggled from the app

## Requirements

- macOS 14 or later
- Apple Silicon (M1 or later) recommended — runs on Intel but first-time preparation takes longer
- **No internet required** after you have the app package

## Setup

1. Open `Flowa.xcodeproj` in Xcode
2. Ensure `Flowa/Models/openai_whisper-large-v3-v20240930_turbo/` is present (~1.5 GB CoreML weights) so Archive includes it
3. Build / Archive / notarize as usual
4. On first launch, grant:
   - **Microphone**
   - **Input Monitoring**
   - **Accessibility**
5. System Settings → Keyboard → set "Press 🌐 key to" → **Do Nothing**
6. Wait for the **Installing Flowa** screen (~2 minutes once per Mac)

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Swift package, added via Xcode's package manager

## License

MIT — see [LICENSE](LICENSE)
