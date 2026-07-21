// TextInserter.swift
// Flowa
//
// Universal text insertion. Two-track behaviour:
//
//   1. ALWAYS write the transcript to the system clipboard. Even if
//      everything else fails, the user can manually Cmd+V it.
//   2. If a target app was captured at Fn-press time AND Accessibility
//      is trusted, synthesise Cmd+V into that app.
//
// Clipboard is intentionally left holding the transcript (no timed
// restore). Restoring after a short delay races slow apps and can
// erase the paste source before they read it.

import Foundation
import AppKit
import ApplicationServices

enum TextInserter {

    enum PasteOutcome: Equatable {
        case clipboardOnly
        case pasted(appName: String?)
        case accessibilityMissing
        case failed
    }

    /// Write `text` to the clipboard and, if possible, paste it into
    /// `targetApp`. Always leaves the transcript on the clipboard.
    @discardableResult
    static func paste(_ text: String, targetApp: NSRunningApplication? = nil) -> PasteOutcome {
        guard !text.isEmpty else { return .failed }
        let pb = NSPasteboard.general

        pb.clearContents()
        let writeOK = pb.setString(text, forType: .string)
        guard writeOK else { return .failed }

        guard let target = targetApp, !target.isTerminated else {
            #if DEBUG
            print("[Flowa][paste] no target app — text is on clipboard only")
            #endif
            return .clipboardOnly
        }

        guard AXIsProcessTrusted() else {
            #if DEBUG
            print("[Flowa][paste] Accessibility not granted — clipboard only")
            #endif
            return .accessibilityMissing
        }

        #if DEBUG
        print("[Flowa][paste] pasting into \(target.localizedName ?? "?") (pid=\(target.processIdentifier))")
        #endif
        target.activate(options: [])

        // Slightly longer activation settle than before; no clipboard restore.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            simulateCmdV()
        }
        return .pasted(appName: target.localizedName)
    }

    // MARK: - Cmd+V synth

    private static let cmdKey: CGKeyCode = 0x37   // left ⌘
    private static let vKey:   CGKeyCode = 0x09   // v

    private static func simulateCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)

        guard
            let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true),
            let vDown   = CGEvent(keyboardEventSource: src, virtualKey: vKey,   keyDown: true),
            let vUp     = CGEvent(keyboardEventSource: src, virtualKey: vKey,   keyDown: false),
            let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false)
        else { return }

        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand

        cmdDown.post(tap: .cgSessionEventTap)
        vDown.post(tap: .cgSessionEventTap)
        vUp.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
    }
}
