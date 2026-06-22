// Transcriber.swift
// Flowa
//
// WhisperKit wrapper. Handles model loading (downloads on first use),
// transcribes a WAV file, returns plain text. Async/await throughout.
//
// Requires the WhisperKit Swift Package to be added to the project:
//   File → Add Package Dependencies… → https://github.com/argmaxinc/WhisperKit
// then add the WhisperKit product to the Flowa app target.
//
// Without the dependency the `import WhisperKit` below will fail to
// compile — that's the intended forcing function.

import Foundation
import Combine

#if canImport(WhisperKit)
import WhisperKit
#endif

@MainActor
final class Transcriber: ObservableObject {

    enum Status: Equatable {
        case idle
        case downloading(progress: Double)   // 0...1 while the model downloads
        case preparing                       // CoreML specialize/compile + tokenizer load
        case ready
        case transcribing
        case error(String)
    }

    @Published private(set) var status: Status = .idle

    /// Fixed to large-v3-turbo — OpenAI's accelerated large-v3
    /// variant released Sept 2024. ≈1.5 GB on disk, 6–8× faster on
    /// Apple Silicon than vanilla large-v3 with essentially identical
    /// accuracy on the languages we care about.
    ///
    /// The CoreML model is *downloaded once* on first launch from the
    /// WhisperKit model hub (≈1.5 GB) — see `loadIfNeeded()`. We keep it
    /// out of the app bundle so the binary stays small. The tiny (~3 MB)
    /// tokenizer *is* bundled, so only the model itself needs the network.
    /// If a bundled model copy is ever present we use it and skip the
    /// download, so the app still works fully offline when shipped that way.
    let modelName: String = "openai_whisper-large-v3-v20240930_turbo"

    /// Which model name we're currently holding open. Kept as a single
    /// variable for future-proofing even though modelName is now const.
    private var loadedModelName: String?

    /// Path to the bundled CoreML model folder inside the .app, or
    /// nil if missing (dev builds without the assets, corrupted
    /// install, etc.).
    private static var bundledModelFolderPath: String? {
        Bundle.main.url(
            forResource: "openai_whisper-large-v3-v20240930_turbo",
            withExtension: nil,
            subdirectory: "Models"
        )?.path
    }

    /// URL to the bundled tokenizer folder inside the .app. WhisperKit
    /// resolves the Whisper tokenizer (vocab + special tokens etc.)
    /// separately from the CoreML model files — both must be local
    /// for first-run dictation to work offline.
    private static var bundledTokenizerFolderURL: URL? {
        Bundle.main.url(
            forResource: "whisper-large-v3",
            withExtension: nil,
            subdirectory: "Models"
        )
    }

    #if canImport(WhisperKit)
    private var pipe: WhisperKit?
    #endif

    /// Loads (or reloads) the model. Safe to call multiple times — a
    /// repeat call is a no-op once the *current* `modelName` is loaded.
    /// If the user picks a different model in the UI, we drop the old
    /// pipe and download / load the new one here.
    func loadIfNeeded() async {
        #if canImport(WhisperKit)
        let wanted = modelName
        if pipe != nil, loadedModelName == wanted { return }
        pipe = nil

        let started = Date()
        do {
            // 1. Resolve the model folder. Prefer a bundled copy if present
            //    (builds that still ship it); otherwise download it once
            //    from the WhisperKit hub, reporting live progress so the
            //    install screen can show a real download bar.
            let modelFolder: String
            if let bundled = Self.bundledModelFolderPath {
                modelFolder = bundled
            } else {
                status = .downloading(progress: 0)
                let url = try await WhisperKit.download(
                    variant: wanted,
                    progressCallback: { progress in
                        Task { @MainActor [weak self] in
                            self?.status = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                )
                modelFolder = url.path
            }

            // 2. Load + specialize the CoreML model for this Mac. With
            //    prewarm+load, this only returns once compilation is done —
            //    so callers can treat `.ready` as "fully usable", which is
            //    what gates the user into the main window.
            status = .preparing
            let config = WhisperKitConfig(
                model: wanted,
                modelFolder: modelFolder,
                tokenizerFolder: Self.bundledTokenizerFolderURL,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false                       // already resolved above
            )
            pipe = try await WhisperKit(config)
            loadedModelName = wanted
            status = .ready
            let elapsed = Int(Date().timeIntervalSince(started))
            print("[Flowa] Whisper: \(wanted) ready in \(elapsed)s")
        } catch {
            status = .error(Self.friendlyLoadError(error))
            print("[Flowa] Whisper: FAILED to load \(wanted): \(error.localizedDescription)")
        }
        #else
        status = .error("WhisperKit not added. File → Add Package Dependencies → https://github.com/argmaxinc/WhisperKit")
        #endif
    }

    /// Map a load/download failure to a short, user-facing sentence for
    /// the install screen. A missing network connection is by far the
    /// most common cause on first launch.
    private static func friendlyLoadError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't download the speech model. Check your internet connection and try again."
        }
        return "Couldn't prepare the speech model. Please try again."
    }

    /// Reads the user's language preference from UserDefaults each call,
    /// so flipping the Home page's Language card takes effect on the
    /// next dictation without restarting. Values are ISO 639-1 codes
    /// ("en", "da", …) or the sentinel "auto" which maps to nil (let
    /// Whisper detect — unreliable on short utterances, opt-in).
    var preferredLanguage: String? {
        let code = UserDefaults.standard.string(forKey: "flowa.language") ?? "en"
        return code == "auto" ? nil : code
    }

    /// Transcribe a single WAV file. Returns plain text, or nil if
    /// nothing intelligible was captured.
    func transcribe(wavFile: URL) async -> String? {
        #if canImport(WhisperKit)
        await loadIfNeeded()
        guard let pipe else { return nil }
        status = .transcribing
        do {
            // The critical bit: WhisperKit's default DecodingOptions
            // assumes English. To unlock the multilingual model we
            // either pass `language: nil` (auto-detect) or set a
            // specific code like "da". Without this Whisper will
            // happily phonetically map Danish words to English.
            // Only override the fields that matter for multilingual.
            // Everything else stays on WhisperKit's defaults — that
            // avoids parameter-name mismatches across versions.
            var options = DecodingOptions()
            options.task = .transcribe
            options.language = preferredLanguage
            options.detectLanguage = (preferredLanguage == nil)
            let results = try await pipe.transcribe(audioPath: wavFile.path,
                                                     decodeOptions: options)
            let text = results.map(\TranscriptionResult.text).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            status = .ready
            return text.isEmpty ? nil : text
        } catch {
            status = .error("Transcription failed: \(error.localizedDescription)")
            return nil
        }
        #else
        status = .error("WhisperKit dependency missing.")
        return nil
        #endif
    }
}
