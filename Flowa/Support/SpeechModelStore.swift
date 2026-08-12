// SpeechModelStore.swift
// Flowa
//
// Bundled speech engine layout + integrity checks. The weights ship inside
// the app (~1.5 GB). We may stage a copy under Application Support when
// CoreML / WhisperKit need a writable path.

import Foundation

enum SpeechModelStore {

    /// Folder name under `Flowa/Models/` and in the app bundle Resources.
    static let modelVariant = "openai_whisper-large-v3-v20240930_turbo"

    /// Writable base for any Hub/tokenizer side-effects (never the app bundle).
    static var preferredDownloadBase: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let base = support
            .appendingPathComponent("Flowa", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        return base
    }

    static var legacyDownloadBase: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents")
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }

    /// Writable staged copy of the bundled engine (preferred load path).
    static var stagedModelFolder: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Flowa", isDirectory: true)
            .appendingPathComponent("SpeechEngine", isDirectory: true)
            .appendingPathComponent(modelVariant, isDirectory: true)
    }

    static func modelFolder(under downloadBase: URL) -> URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelVariant, isDirectory: true)
    }

    static func looksComplete(_ folder: URL) -> Bool {
        let fm = FileManager.default
        let config = folder.appendingPathComponent("config.json")
        let encoder = folder.appendingPathComponent("AudioEncoder.mlmodelc")
        let encoderWeights = encoder
            .appendingPathComponent("weights", isDirectory: true)
            .appendingPathComponent("weight.bin")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: config.path),
              fm.fileExists(atPath: encoder.path, isDirectory: &isDir),
              isDir.boolValue,
              fm.fileExists(atPath: encoderWeights.path) else {
            return false
        }
        // Guard against truncated copies (full encoder weights are ~1.2 GB).
        if let attrs = try? fm.attributesOfItem(atPath: encoderWeights.path),
           let size = attrs[.size] as? NSNumber {
            if size.int64Value < 500_000_000 { return false }
        }
        return true
    }

    /// Prefer staged App Support copy → bundle → legacy caches.
    static func resolveLocalModelFolder(bundledPath: String?) -> String? {
        if looksComplete(stagedModelFolder) {
            return stagedModelFolder.path
        }
        if let bundledPath {
            let url = URL(fileURLWithPath: bundledPath, isDirectory: true)
            if looksComplete(url) { return bundledPath }
        }
        for folder in [
            modelFolder(under: preferredDownloadBase),
            modelFolder(under: legacyDownloadBase)
        ] where looksComplete(folder) {
            return folder.path
        }
        return nil
    }

    /// Ensure a complete engine exists at a writable path.
    /// Copies from the bundle on first install (one-time, offline).
    static func ensureWritableModel(bundledPath: String?) throws -> String {
        if looksComplete(stagedModelFolder) {
            return stagedModelFolder.path
        }
        guard let bundledPath else {
            throw NSError(
                domain: "Flowa.SpeechModelStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Speech engine is missing from this app. Reinstall Flowa from the original package."]
            )
        }
        let source = URL(fileURLWithPath: bundledPath, isDirectory: true)
        guard looksComplete(source) else {
            throw NSError(
                domain: "Flowa.SpeechModelStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Speech engine in the app is incomplete. Reinstall Flowa from the original package."]
            )
        }

        let fm = FileManager.default
        let parent = stagedModelFolder.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: stagedModelFolder.path) {
            try fm.removeItem(at: stagedModelFolder)
        }
        try fm.copyItem(at: source, to: stagedModelFolder)

        guard looksComplete(stagedModelFolder) else {
            try? fm.removeItem(at: stagedModelFolder)
            throw NSError(
                domain: "Flowa.SpeechModelStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't install the speech engine. Check free disk space and try again."]
            )
        }
        return stagedModelFolder.path
    }

    static func cacheFoldersToClear() -> [URL] {
        [
            stagedModelFolder,
            modelFolder(under: preferredDownloadBase),
            modelFolder(under: legacyDownloadBase)
        ]
    }

    /// Removes staged / legacy caches only — never the app bundle.
    @discardableResult
    static func clearDownloadedModels(
        fileManager: FileManager = .default
    ) -> [URL] {
        var removed: [URL] = []
        for folder in cacheFoldersToClear() {
            if fileManager.fileExists(atPath: folder.path) {
                try? fileManager.removeItem(at: folder)
                removed.append(folder)
            }
        }
        return removed
    }
}
