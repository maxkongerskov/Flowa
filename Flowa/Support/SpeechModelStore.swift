// SpeechModelStore.swift
// Flowa
//
// Bundled speech engine layout + integrity checks. The weights ship inside
// the app (~1.5 GB). Legacy download folders are only cleared on repair.

import Foundation

enum SpeechModelStore {

    /// Folder name under `Flowa/Models/` and in the app bundle Resources.
    static let modelVariant = "openai_whisper-large-v3-v20240930_turbo"

    /// Historical download locations (pre-bundled builds). Not used for install.
    static var preferredDownloadBase: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Flowa", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
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
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: config.path),
              fm.fileExists(atPath: encoder.path, isDirectory: &isDir),
              isDir.boolValue else {
            return false
        }
        return true
    }

    /// Prefer the model shipped in the app. Fall back to old download caches
    /// only if the bundle is incomplete (dev / partial builds).
    static func resolveLocalModelFolder(bundledPath: String?) -> String? {
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

    static func cacheFoldersToClear() -> [URL] {
        [
            modelFolder(under: preferredDownloadBase),
            modelFolder(under: legacyDownloadBase)
        ]
    }

    /// Removes legacy *downloaded* caches only — never the app bundle.
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
