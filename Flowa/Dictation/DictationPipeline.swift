// DictationPipeline.swift
// Flowa
//
// Coordinates the full dictation loop:
//
//   GlobalHotkey  →  pipeline.start(target:, mic:)  →  AudioCapture
//   GlobalHotkey  →  pipeline.commit(language:)     →  stop → WAV →
//                                                      Transcriber → paste
//
// Transcription is single-flight: a new commit waits for / replaces
// the previous job so rapid fn taps cannot stack Whisper runs.

import Foundation
import AppKit
import Combine

/// One completed dictation. Persisted so the Recent list survives relaunches.
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

/// Pure recent-list ring helper — unit-tested without AV/AppKit side effects.
enum RecentRing {
    static func inserting(_ entry: Dictation, into items: [Dictation], limit: Int) -> [Dictation] {
        var next = items
        next.insert(entry, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }
}

@MainActor
final class DictationPipeline: ObservableObject {

    let audio = AudioCapture()
    let transcriber = Transcriber()

    /// Target app captured when the current recording session started.
    /// Cleared on commit/cancel; not public for external mutation.
    private var sessionTargetApp: NSRunningApplication?

    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var recent: [Dictation] = []
    /// True while a Whisper job is running (for menu bar / UI).
    @Published private(set) var isTranscribing: Bool = false

    private let recentLimit = 100
    /// Serialises transcription work so commits never pile up.
    private var transcriptionTask: Task<Void, Never>?

    init() {
        self.recent = Self.loadFromDisk()
    }

    func clearRecent() {
        recent.removeAll()
        Self.saveToDisk(recent)
    }

    func dismissError() {
        lastErrorMessage = nil
    }

    /// Called when the user hits Fn but Whisper is not ready yet.
    func surfaceModelNotReady() {
        if case .error(let message) = transcriber.status {
            lastErrorMessage = message
        } else if case .downloading = transcriber.status {
            lastErrorMessage = "Still downloading the speech engine. Check the main window."
        } else if case .preparing = transcriber.status {
            lastErrorMessage = "Still installing Flowa on this Mac. Try again in a moment."
        } else {
            lastErrorMessage = "Flowa isn't finished installing yet. Check the main window."
        }
    }

    /// In-app reinstall of the speech model without a full permissions reset.
    func reinstallSpeechModel() {
        lastErrorMessage = nil
        transcriber.resetForReinstall(clearCache: true)
        NotificationCenter.default.post(name: .flowaShowMainWindow, object: nil)
        Task { await transcriber.loadIfNeeded() }
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

    func prewarm() {
        Task { await transcriber.loadIfNeeded() }
    }

    // MARK: - Lifecycle

    /// Start recording for `targetApp` using the given microphone UID
    /// (`"default"` / empty = system default). Binds the paste target
    /// to this session.
    @discardableResult
    func start(targetApp: NSRunningApplication?, microphoneUID: String) -> Bool {
        lastErrorMessage = nil
        sessionTargetApp = targetApp
        do {
            try audio.start(
                deviceUID: microphoneUID,
                maxDuration: Preferences.maxDurationSeconds
            )
            return true
        } catch {
            sessionTargetApp = nil
            let details = String(describing: error)
            // Prefer localized description when we threw a user-facing NSError.
            let ns = error as NSError
            if ns.domain == "AudioCapture", let msg = ns.userInfo[NSLocalizedDescriptionKey] as? String {
                lastErrorMessage = msg
            } else {
                lastErrorMessage = "Couldn't start recording. Check your microphone and try again."
            }
            print("[Flowa] pipeline.start FAILED: \(error) — full: \(details)")
            return false
        }
    }

    /// Stop audio, snapshot the session target, and transcribe with the
    /// given Whisper language (nil = auto-detect).
    func commit(language: String?) {
        let wasSilent = audio.appearsSilent
        let deviceKind = audio.sessionDeviceKind
        let peak = audio.sessionPeakLevel
        let hitMax = audio.stoppedForMaxDuration
        let maxMinutes = Preferences.maxDurationMinutes

        guard let wavURL = audio.stop() else {
            sessionTargetApp = nil
            if wasSilent {
                lastErrorMessage = Self.silenceMessage(kind: deviceKind)
            }
            return
        }

        // Near-silent take: skip Whisper and surface a clear tip.
        if wasSilent {
            print("[Flowa] commit skipped — silent take peak=\(peak) kind=\(deviceKind)")
            try? FileManager.default.removeItem(at: wavURL)
            sessionTargetApp = nil
            lastErrorMessage = Self.silenceMessage(kind: deviceKind)
            return
        }

        let capturedTarget = sessionTargetApp
        sessionTargetApp = nil

        // Single-flight: queue so only one runTranscription runs at a time.
        let previous = transcriptionTask
        transcriptionTask = Task { @MainActor in
            _ = await previous?.value
            await self.runTranscription(
                wavURL: wavURL,
                targetApp: capturedTarget,
                language: language,
                hitMaxDuration: hitMax,
                maxMinutes: maxMinutes
            )
        }
    }

    private static func silenceMessage(kind: MicDeviceKind) -> String {
        switch kind {
        case .continuity:
            return "No speech heard from the iPhone mic. Hold the phone near your mouth and try again — Continuity picks up the phone, not the Mac."
        case .standard:
            return "No speech heard. Check the selected microphone and try again."
        }
    }

    func cancel() {
        audio.cancel()
        sessionTargetApp = nil
    }

    // MARK: - Transcription + paste

    private func runTranscription(wavURL: URL,
                                  targetApp: NSRunningApplication?,
                                  language: String?,
                                  hitMaxDuration: Bool,
                                  maxMinutes: Int) async {
        isTranscribing = true
        defer { isTranscribing = false }

        await transcriber.loadIfNeeded()

        let started = Date()
        guard let text = await transcriber.transcribe(wavFile: wavURL, language: language) else {
            if let decode = transcriber.lastDecodeErrorMessage {
                lastErrorMessage = decode
            } else if case .error(let message) = transcriber.status {
                lastErrorMessage = message
            } else {
                lastErrorMessage = "Couldn't understand that audio. Try speaking more clearly or check the microphone."
            }
            // If the model itself failed, open the install/repair UI.
            if transcriber.needsSetup {
                NotificationCenter.default.post(name: .flowaShowMainWindow, object: nil)
            }
            print("[Flowa] transcription produced no text")
            try? FileManager.default.removeItem(at: wavURL)
            return
        }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))

        let outcome = TextInserter.paste(text, targetApp: targetApp)
        switch outcome {
        case .accessibilityMissing:
            // Soft tip — text is on the clipboard.
            if lastErrorMessage == nil {
                lastErrorMessage = "Transcript is on the clipboard (Accessibility is off for auto-paste)."
            }
        case .failed:
            lastErrorMessage = "Couldn't copy the transcript to the clipboard."
        case .clipboardOnly, .pasted:
            break
        }

        #if DEBUG
        let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
        let target = targetApp?.localizedName ?? "<clipboard only>"
        print("[Flowa] ✓ \(elapsed)s · \"\(preview)\" → \(target) outcome=\(outcome)")
        #else
        print("[Flowa] ✓ transcribed in \(elapsed)s")
        #endif

        let entry = Dictation(
            text: text,
            targetAppName: targetApp?.localizedName,
            date: Date()
        )
        recent = RecentRing.inserting(entry, into: recent, limit: recentLimit)
        Self.saveToDisk(recent)

        if hitMaxDuration {
            let label = maxMinutes >= 60 && maxMinutes % 60 == 0
                ? "\(maxMinutes / 60) hour\(maxMinutes == 60 ? "" : "s")"
                : "\(maxMinutes) minute\(maxMinutes == 1 ? "" : "s")"
            lastErrorMessage = "Recording stopped at your \(label) limit. Transcript was still saved."
        }

        try? FileManager.default.removeItem(at: wavURL)
    }
}

// MARK: - JSON config

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
