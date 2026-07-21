// Transcriber.swift
// Flowa
//
// WhisperKit wrapper. The CoreML speech model ships inside the app bundle
// (~1.5 GB). First launch on each Mac only specializes it for this chip
// (typically ~1–2 minutes, offline). No network download.

import Foundation
import Combine
import WhisperKit

@MainActor
final class Transcriber: ObservableObject {

    enum Status: Equatable {
        case idle
        /// CoreML specialize / load. `progress` is 0...1 over
        /// `expectedPrepareSeconds` (~2 min countdown in the install UI).
        case preparing(progress: Double)
        case ready
        case transcribing
        case error(String)
    }

    /// Install countdown length shown to the user (~2 minutes).
    static let expectedPrepareSeconds: TimeInterval = 120

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
        case .error, .preparing:
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

    /// Drop the in-memory pipeline so the next load re-prepares from the bundle.
    /// `clearCache` only wipes legacy download folders (not the bundled model).
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
            guard let modelFolder = SpeechModelStore.resolveLocalModelFolder(
                bundledPath: Self.bundledModelFolderPath
            ) else {
                throw NSError(
                    domain: "Flowa.Transcriber",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Speech engine is missing from this app. Reinstall Flowa from the original package."]
                )
            }

            startPrepareProgress()
            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: modelFolder,
                tokenizerFolder: Self.bundledTokenizerFolderURL,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            pipe = try await WhisperKit(config)
            stopPrepareProgress()
            isLoaded = true
            status = .ready
            Preferences.markSpeechModelInstalled()
            let elapsed = Int(Date().timeIntervalSince(started))
            print("[Flowa] Whisper ready in \(elapsed)s (bundled) from \(modelFolder)")
        } catch {
            stopPrepareProgress()
            pipe = nil
            isLoaded = false
            Preferences.markSpeechModelNotInstalled()
            status = .error(Self.friendlyLoadError(error))
            print("[Flowa] Whisper FAILED: \(error.localizedDescription)")
        }
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
                // Cap under 1.0 until WhisperKit actually finishes.
                if case .preparing = self.status {
                    // Allow progress to reach 1.0 so the UI countdown can
                    // show “Almost done…” if CoreML takes longer than 2 min.
                    self.status = .preparing(progress: min(1.0, max(0, fraction)))
                } else {
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopPrepareProgress() {
        prepareProgressTask?.cancel()
        prepareProgressTask = nil
    }

    private static func friendlyLoadError(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("space") || text.contains("disk") {
            return "Couldn't finish installation — your Mac may be low on disk space."
        }
        if text.contains("missing") {
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
