// TextInserter.swift
// Flowa
//
// Universal text insertion. Two-track behaviour:
//
//   1. ALWAYS write the transcript to the system clipboard. Even if
//      everything else fails, the user can manually Cmd+V it.
//   2. If a target app was captured at Fn-press time AND Accessibility
//      permission is granted, also synthesise Cmd+V into that app so
//      the paste lands without manual intervention.
//
// Without Accessibility the synthesised Cmd+V is silently dropped by
// macOS; we don't fight it — the clipboard write is the fallback.

import Foundation
import AppKit
import ApplicationServices

enum TextInserter {

    /// Write `text` to the clipboard and, if possible, paste it into
    /// `targetApp`. Returns true if the clipboard write succeeded
    /// (which is the floor of "success" — the user can always Cmd+V).
    @discardableResult
    static func paste(_ text: String, targetApp: NSRunningApplication? = nil) -> Bool {
        guard !text.isEmpty else { return false }
        let pb = NSPasteboard.general

        // Snapshot so we can restore the user's clipboard later — but
        // only if nothing else writes to it in the meantime.
        let snapshot = ClipboardSnapshot(pasteboard: pb)

        pb.clearContents()
        let writeOK = pb.setString(text, forType: .string)
        let countAfterOurWrite = pb.changeCount

        // If we have no target, we're done: text is on the clipboard.
        guard let target = targetApp, !target.isTerminated else {
            #if DEBUG
            print("[Flowa][paste] no target app — text is on clipboard only")
            #endif
            return writeOK
        }

        #if DEBUG
        print("[Flowa][paste] pasting into \(target.localizedName ?? "?") (pid=\(target.processIdentifier))")
        #endif
        // Re-activate the target so the synthetic Cmd+V lands in the
        // right window even if focus has drifted during transcription.
        target.activate(options: [])

        // Wait for activation to take effect, then synth Cmd+V, then
        // restore the clipboard if it hasn't been touched by anyone
        // else in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            simulateCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                if pb.changeCount == countAfterOurWrite {
                    snapshot.restore(to: pb)
                }
            }
        }
        return writeOK
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

        // Post to the session event tap — reaches whichever app is
        // currently key (we re-activated the target just before this call).
        cmdDown.post(tap: .cgSessionEventTap)
        vDown.post(tap: .cgSessionEventTap)
        vUp.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
    }
}

// MARK: - Clipboard snapshot

private struct ClipboardSnapshot {
    /// All pasteboard items captured by type+payload. Restoring
    /// preserves richer content (RTF, images, file URLs) when the
    /// user's clipboard had something other than plain text.
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        var snap: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            snap.append(dict)
        }
        self.items = snap
    }

    func restore(to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
