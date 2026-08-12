# Flowa

Voice dictation for macOS. Press `fn`, speak, press `fn` again — your words appear wherever your cursor is.

Runs entirely on your Mac after setup. No subscription, no cloud transcription, no audio leaving your machine.

## How it works

1. Press `fn` — recording starts, a small floating bar appears
2. Speak for as long as you want (any language, mid-sentence switching is fine)
3. Press `fn` again — Flowa transcribes and pastes the text into whatever app you were using

That's it.

## Features

- **Local transcription** — after first setup, speech runs on-device
- **Any language** — 99 languages supported. Switch languages mid-session; Flowa picks it up automatically
- **Works everywhere** — dictates into any app: notes, email, chat, code editors, browsers
- **Menu bar icon** — stays running in the background, always ready
- **Recent history** — last 100 dictations saved locally, copyable from the Home screen
- **Launch at login** — optional, toggled from the app

## Requirements

- macOS 14 or later
- Apple Silicon (M1 or later) recommended — runs on Intel but first-time preparation takes longer
- Internet **once** on first launch if you built from this repo (to fetch the ~1.5 GB speech engine)

## Build from this repo

The speech engine is **not** committed to git (it is ~1.5 GB). Anyone can still use the repo:

```bash
git clone https://github.com/maxkongerskov/Flowa.git
cd Flowa
open Flowa.xcodeproj
```

1. In Xcode, select your **Team** under Signing & Capabilities
2. Build and run (⌘R)
3. On first launch, grant **Microphone**, **Input Monitoring**, and **Accessibility**
4. System Settings → Keyboard → set "Press 🌐 key to" → **Do Nothing**
5. Flowa will **download the speech engine once** (~1.5 GB from the [WhisperKit CoreML hub](https://huggingface.co/argmaxinc/whisperkit-coreml)), then prepare it for your Mac (~10 minutes). Keep the app open.

After that, Flowa works offline.

### Optional: ship a fully offline app package

If you want the engine **inside** the `.app` (no first-run download for end users):

1. Place a complete copy at  
   `Flowa/Models/openai_whisper-large-v3-v20240930_turbo/`  
   (same layout as on [Hugging Face](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo))
2. Archive / notarize as usual — the model is copied into the app bundle
3. First launch only specializes CoreML for that Mac (still ~10 minutes, offline)

`scripts/notarize.sh` verifies the bundled model is present before export.

## Dependencies

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — Swift package (Xcode package manager)
- Speech engine weights from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) (`openai_whisper-large-v3-v20240930_turbo`)

## License

MIT — see [LICENSE](LICENSE)
