// DictationPipeline.swift
// Flowa
//
// Coordinates the full dictation loop:
//
//   GlobalHotkey  →  pipeline.start()  →  AudioCapture starts
//   GlobalHotkey  →  pipeline.commit() →  AudioCapture stops →
//                                         WAV file →
//                                         Transcriber.transcribe →
//                                         TextInserter.paste
//
// Also keeps a small in-memory ring of recent transcripts for the
// Home page's "Recent" list. Persistence to disk lands later.

import Foundation
import AppKit
import ApplicationServices
import Combine

/// One completed dictation. Persisted to disk so the Recent list
/// survives app relaunches and reboots.
struct Dictation: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let targetAppName: String?
    let date: Date

    init(id: UUID = UUID(),
         text: String,
         targetAppName: String?,
         date: Date) {
        self.id = id
        self.text = text
        self.targetAppName = targetAppName
        self.date = date
    }
}

@MainActor
final class DictationPipeline: ObservableObject {

    let audio = AudioCapture()
    let transcriber = Transcriber()

    /// The app that was frontmost when dictation started — the paste
    /// target. Captured by GlobalHotkey on Fn DOWN; re-activated
    /// before the synthetic Cmd+V so it lands in the right window.
    var targetApp: NSRunningApplication?

    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastPasteFailed: Bool = false

    /// Ring of recent dictations, newest first. Capped at `recentLimit`.
    /// Loaded from disk on init and resaved on every change.
    @Published private(set) var recent: [Dictation] = []
    private let recentLimit = 100

    init() {
        self.recent = Self.loadFromDisk()
    }

    /// Wipe the recent list — used by the Clear button on Home.
    func clearRecent() {
        recent.removeAll()
        Self.saveToDisk(recent)
    }

    // MARK: - Persistence

    private static var storageURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("Flowa", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recent.json")
    }

    private static func loadFromDisk() -> [Dictation] {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder.flowa.decode([Dictation].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveToDisk(_ items: [Dictation]) {
        guard let data = try? JSONEncoder.flowa.encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    /// Kick off model loading early so the first dictation isn't slow.
    /// Called by FlowaApp.onAppear.
    func prewarm() {
        Task { await transcriber.loadIfNeeded() }
    }

    // MARK: - Lifecycle

    func start() {
        do {
            try audio.start()
        } catch {
            print("[Flowa] pipeline.start FAILED: \(error.localizedDescription)")
        }
    }

    func commit() {
        guard let wavURL = audio.stop() else { return }
        Task { await runTranscription(wavURL: wavURL) }
    }

    func cancel() {
        audio.cancel()
    }

    // MARK: - Transcription + paste

    private func runTranscription(wavURL: URL) async {
        await transcriber.loadIfNeeded()

        let started = Date()
        guard let text = await transcriber.transcribe(wavFile: wavURL) else {
            print("[Flowa] transcription produced no text")
            try? FileManager.default.removeItem(at: wavURL)
            return
        }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))

        lastTranscript = text
        let ok = TextInserter.paste(text, targetApp: targetApp)
        lastPasteFailed = !ok

        let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
        let target = targetApp?.localizedName ?? "<clipboard only>"
        print("[Flowa] ✓ \(elapsed)s · \"\(preview)\" → \(target)")

        // Record this dictation so the Home page can list it, and
        // persist immediately so a crash / quit can't lose it.
        let entry = Dictation(
            text: text,
            targetAppName: targetApp?.localizedName,
            date: Date()
        )
        recent.insert(entry, at: 0)
        if recent.count > recentLimit {
            recent = Array(recent.prefix(recentLimit))
        }
        Self.saveToDisk(recent)

        // Best-effort temp file cleanup.
        try? FileManager.default.removeItem(at: wavURL)
    }
}

// MARK: - JSON config
//
// One ISO-8601 encoder/decoder pair used by the persistence layer so
// dates round-trip cleanly across app versions and (eventually) for
// hand-inspection of the file.

private extension JSONEncoder {
    static let flowa: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let flowa: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
