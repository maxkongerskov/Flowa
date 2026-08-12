// Transcriber.swift
// Flowa
//
// WhisperKit wrapper. Prefer a local engine (bundled / staged / cache).
// If missing — normal for builds from the public git repo — download once
// from the WhisperKit hub (~1.5 GB), then CoreML-specialize for this Mac.

import Foundation
import Combine
import WhisperKit

@MainActor
final class Transcriber: ObservableObject {

    enum Status: Equatable {
        case idle
        /// Hub download of the CoreML weights (0...1). Only when not already local.
        case downloading(progress: Double)
        /// CoreML specialize / load. `progress` is 0...1 for the ~10 min countdown.
        case preparing(progress: Double)
        case ready
        case transcribing
        case error(String)
    }

    /// Countdown length in the install UI (~10 minutes). First CoreML
    /// specialize on a new Mac often takes 5–10+ minutes for the engine.
    static let expectedPrepareSeconds: TimeInterval = 10 * 60

    /// Hard cap so we never spin forever on a stuck CoreML load.
    static let prepareTimeoutSeconds: TimeInterval = 20 * 60

    @Published private(set) var status: Status = .idle

    let modelName: String = SpeechModelStore.modelVariant

    /// Last decode failure (model was loaded; audio could not be transcribed).
    private(set) var lastDecodeErrorMessage: String?

    private var isLoaded: Bool = false
    private var loadTask: Task<Void, Never>?
    private var prepareProgressTask: Task<Void, Never>?

    private static var bundledModelFolderPath: String? {
        Bundle.main.url(
            forResource: SpeechModelStore.modelVariant,
            withExtension: nil,
            subdirectory: "Models"
        )?.path
    }

    private static var bundledTokenizerFolderURL: URL? {
        Bundle.main.url(
            forResource: "whisper-large-v3",
            withExtension: nil,
            subdirectory: "Models"
        )
    }

    private var pipe: WhisperKit?

    var isReady: Bool {
        isLoaded && pipe != nil && (status == .ready || status == .transcribing)
    }

    /// After onboarding, Home stays blocked until the engine is ready.
    var needsSetup: Bool {
        switch status {
        case .ready, .transcribing:
            return false
        case .error, .preparing, .downloading:
            return true
        case .idle:
            return !isLoaded
        }
    }

    func loadIfNeeded() async {
        if pipe != nil, isLoaded {
            if status != .ready && status != .transcribing {
                status = .ready
            }
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor in
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Drop the in-memory pipeline so the next load re-prepares.
    func resetForReinstall(clearCache: Bool) {
        loadTask?.cancel()
        loadTask = nil
        stopPrepareProgress()
        pipe = nil
        isLoaded = false
        lastDecodeErrorMessage = nil
        if clearCache {
            SpeechModelStore.clearDownloadedModels()
        }
        Preferences.markSpeechModelNotInstalled()
        status = .idle
    }

    private func performLoad() async {
        if pipe != nil, isLoaded {
            status = .ready
            Preferences.markSpeechModelInstalled()
            return
        }
        pipe = nil
        isLoaded = false

        let started = Date()
        do {
            let modelFolder = try await resolveOrDownloadModelFolder()

            // prewarm:false — prewarm loads every CoreML model twice and
            // roughly doubles first-install time (looked like a hang at “Almost done”).
            startPrepareProgress()
            let modelName = self.modelName
            let tokenizerFolder = Self.bundledTokenizerFolderURL
            let downloadBase = SpeechModelStore.preferredDownloadBase

            let kit = try await withThrowingTaskGroup(of: WhisperKit.self) { group in
                group.addTask {
                    let config = WhisperKitConfig(
                        model: modelName,
                        downloadBase: downloadBase,
                        modelFolder: modelFolder,
                        tokenizerFolder: tokenizerFolder,
                        verbose: false,
                        logLevel: .error,
                        prewarm: false,
                        load: true,
                        download: false
                    )
                    return try await WhisperKit(config)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Self.prepareTimeoutSeconds * 1_000_000_000))
                    throw NSError(
                        domain: "Flowa.Transcriber",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Installation is taking too long. Free some disk space, quit other apps, and try again."]
                    )
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            stopPrepareProgress()
            pipe = kit
            isLoaded = true
            status = .ready
            Preferences.markSpeechModelInstalled()
            let elapsed = Int(Date().timeIntervalSince(started))
            print("[Flowa] Whisper ready in \(elapsed)s from \(modelFolder)")
        } catch is CancellationError {
            stopPrepareProgress()
            pipe = nil
            isLoaded = false
            if case .preparing = status {
                status = .idle
            }
            if case .downloading = status {
                status = .idle
            }
        } catch {
            stopPrepareProgress()
            pipe = nil
            isLoaded = false
            Preferences.markSpeechModelNotInstalled()
            status = .error(Self.friendlyLoadError(error))
            print("[Flowa] Whisper FAILED: \(error.localizedDescription)")
        }
    }

    /// Local engine if present; otherwise one-time hub download (~1.5 GB).
    private func resolveOrDownloadModelFolder() async throws -> String {
        if let local = SpeechModelStore.resolveLocalModelFolder(
            bundledPath: Self.bundledModelFolderPath
        ) {
            // Stage out of a read-only app bundle when that's the source.
            if let bundled = Self.bundledModelFolderPath,
               (local as NSString).standardizingPath == (bundled as NSString).standardizingPath {
                return try SpeechModelStore.ensureWritableModel(bundledPath: bundled)
            }
            return local
        }

        // Public git builds ship without the ~1.5 GB weights. Pull once.
        status = .downloading(progress: 0)
        print("[Flowa] No local speech engine — downloading \(modelName)…")
        let url = try await WhisperKit.download(
            variant: modelName,
            downloadBase: SpeechModelStore.preferredDownloadBase,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    self?.status = .downloading(progress: progress.fractionCompleted)
                }
            }
        )

        guard SpeechModelStore.looksComplete(url) else {
            throw NSError(
                domain: "Flowa.Transcriber",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey:
                    "Download finished but the speech engine looks incomplete. Check free disk space and try again."]
            )
        }
        print("[Flowa] Downloaded speech engine to \(url.path)")
        return url.path
    }

    private func startPrepareProgress() {
        stopPrepareProgress()
        status = .preparing(progress: 0)
        let duration = Self.expectedPrepareSeconds
        prepareProgressTask = Task { @MainActor [weak self] in
            let start = Date()
            while !Task.isCancelled {
                guard let self else { return }
                let fraction = Date().timeIntervalSince(start) / duration
                if case .preparing = self.status {
                    // Cap at 0.99 so the UI can distinguish “countdown finished,
                    // still working” (progress ~1) without claiming finished.
                    self.status = .preparing(progress: min(0.99, max(0, fraction)))
                } else {
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func stopPrepareProgress() {
        prepareProgressTask?.cancel()
        prepareProgressTask = nil
    }

    private static func friendlyLoadError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't download the speech engine. Check your internet connection and try again."
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("network") || text.contains("offline") || text.contains("internet")
            || text.contains("timed out") || text.contains("hostname") {
            return "Couldn't download the speech engine. Check your internet connection and try again."
        }
        if text.contains("space") || text.contains("disk") {
            return "Couldn't finish installation — your Mac may be low on disk space."
        }
        if text.contains("missing") || text.contains("incomplete") || text.contains("package")
            || text.contains("download") {
            return error.localizedDescription
        }
        if text.contains("too long") {
            return error.localizedDescription
        }
        return "Couldn't finish installation. Try again, or use Repair Flowa from the menu bar."
    }

    func transcribe(wavFile: URL, language: String?) async -> String? {
        lastDecodeErrorMessage = nil
        await loadIfNeeded()
        guard let pipe else {
            if case .error(let message) = status {
                lastDecodeErrorMessage = message
            } else {
                lastDecodeErrorMessage = "Speech engine isn't ready yet."
            }
            return nil
        }
        status = .transcribing
        do {
            var options = DecodingOptions()
            options.task = .transcribe
            options.language = language
            options.detectLanguage = (language == nil)
            let results = try await pipe.transcribe(audioPath: wavFile.path,
                                                     decodeOptions: options)
            let text = results.map(\TranscriptionResult.text).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            status = .ready
            return text.isEmpty ? nil : text
        } catch {
            lastDecodeErrorMessage = "Transcription failed: \(error.localizedDescription)"
            status = isLoaded ? .ready : .error(lastDecodeErrorMessage ?? "Transcription failed.")
            return nil
        }
    }
}
