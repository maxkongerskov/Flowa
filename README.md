# Flowa

Voice dictation for macOS. Runs entirely on your Mac.

## Status

**Phase 0 — app skeleton.** Sidebar layout, Pro Gray theme, global Fn-hotkey, floating Flow Bar. No transcription yet — WhisperKit integration arrives in Phase 1.

## Open

```
open /Users/maxkongerskov/Downloads/Flowa/Flowa.xcodeproj
```

Build (⌘B), run (⌘R). The window opens with the seven Hub sections in the sidebar: Home, Insights, Dictionary, Snippets, Style, Transforms, Scratchpad.

## What works in Phase 0

- **Sidebar navigation** — click between the 7 sections, each renders with banner + placeholder content
- **Pro Gray theme** — neutral light grey background, near-black accent, blue reserved for Insights stats
- **Settings modal** — opens from sidebar footer; inner sidebar with General / System / Vibe coding / Experimental / Account
- **Global Fn-hotkey** — same engine as Vani: hold Fn pops the Flow Bar, release commits; double-tap enters record mode
- **Flow Bar** — small floating pill (X · waveform · ✓) at the bottom-centre of the screen, matches Wispr's design
- **Fn conflict detector** — warns on Home if Apple's "Press 🌐 key to" is set to anything but "Do Nothing"

## What's NOT in Phase 0 (by design)

- Transcription (Phase 1, WhisperKit)
- Universal paste into focused app (Phase 1)
- Real audio levels in the Flow Bar waveform (Phase 1, currently placeholder animation)
- Dictionary CRUD (Phase 3)
- Snippets engine (Phase 3)
- Style tone-prompts (Phase 2)
- Transforms (Phase 5)
- Real history (Phase 1)
- Persistence (Phase 3)
- App icon (Phase 6)

## Permissions you'll need to grant

1. **Microphone** — auto-prompts when transcription is wired up (Phase 1)
2. **Input Monitoring** — required NOW for the Fn detection. Click the conflict banner if it appears, or open System Settings → Privacy & Security → Input Monitoring manually and add Flowa
3. **Disable Apple's Fn handler** — System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing". Without this, macOS shows emoji picker / starts system dictation before Flowa sees the keypress

## File structure

```
Flowa/
├── README.md
├── Flowa.xcodeproj/
└── Flowa/
    ├── FlowaApp.swift           ← entry point
    ├── Theme.swift              ← Pro Gray palette + type ramps
    ├── RootView.swift           ← sidebar + content layout
    ├── Sidebar.swift            ← 7-item navigation
    ├── Components/
    │   ├── BannerCard.swift     ← reusable hero banner (Wispr-style)
    │   ├── SectionShell.swift   ← title + scrollable content wrapper
    │   └── SettingsModal.swift  ← modal with inner sidebar (General/System/Vibe/Experimental/Account)
    ├── Sections/
    │   ├── HomeView.swift
    │   ├── InsightsView.swift
    │   ├── DictionaryView.swift
    │   ├── SnippetsView.swift
    │   ├── StyleView.swift
    │   ├── TransformsView.swift
    │   └── ScratchpadView.swift
    └── Hotkey/
        ├── GlobalHotkey.swift   ← CGEventTap-based Fn detection
        ├── FnConflictDetector.swift
        └── FloatingPanel.swift  ← borderless NSPanel + Flow Bar pill
```

## Roadmap

- **Phase 1** — WhisperKit dependency, audio capture, real transcription in Flow Bar, universal paste
- **Phase 2** — Auto Cleanup (4 levels), filler removal, auto-punctuation
- **Phase 3** — Dictionary + Snippets + per-app Styles
- **Phase 4** — History view, search, retry
- **Phase 5** — Transforms, Scratchpad, Insights real metrics
- **Phase 6** — App icon, edge cases, polish

Total estimate: ~6-7 weeks of focused work for Wispr parity on a single Mac.
