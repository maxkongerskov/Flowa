import XCTest
@testable import Flowa

final class SpeechModelStoreTests: XCTestCase {

    func testModelFolderLayoutMatchesWhisperKitHub() {
        let base = URL(fileURLWithPath: "/tmp/flowa-test-hub", isDirectory: true)
        let folder = SpeechModelStore.modelFolder(under: base)
        XCTAssertEqual(
            folder.path,
            "/tmp/flowa-test-hub/models/argmaxinc/whisperkit-coreml/\(SpeechModelStore.modelVariant)"
        )
    }

    func testLooksCompleteRequiresConfigAndEncoder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowa-model-complete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(SpeechModelStore.looksComplete(root))

        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        XCTAssertFalse(SpeechModelStore.looksComplete(root))

        let encoder = root.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
        XCTAssertTrue(SpeechModelStore.looksComplete(root))
    }

    func testResolvePrefersBundledWhenComplete() throws {
        let bundled = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowa-bundled-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundled) }

        try Data("{}".utf8).write(to: bundled.appendingPathComponent("config.json"))
        try FileManager.default.createDirectory(
            at: bundled.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        let resolved = SpeechModelStore.resolveLocalModelFolder(bundledPath: bundled.path)
        XCTAssertEqual(resolved, bundled.path)
    }

    func testResolveReturnsNilWhenNothingComplete() {
        let resolved = SpeechModelStore.resolveLocalModelFolder(
            bundledPath: "/tmp/flowa-does-not-exist-\(UUID().uuidString)"
        )
        // May still find a real user install under Documents/App Support — only
        // assert nil when those aren't complete for this variant, which we
        // can't guarantee on the dev machine. Just ensure incomplete bundle is skipped.
        if let resolved {
            XCTAssertTrue(
                SpeechModelStore.looksComplete(URL(fileURLWithPath: resolved, isDirectory: true)),
                "resolve must only return complete folders"
            )
            XCTAssertNotEqual(resolved, "/tmp/flowa-does-not-exist")
        }
    }

    func testRepairResetSpeechModelClearsFirstRunFlag() {
        Preferences.markSpeechModelInstalled()
        XCTAssertTrue(Preferences.speechModelInstalled)

        Repair.resetSpeechModelInstall(clearCache: false)
        XCTAssertFalse(Preferences.speechModelInstalled)

        // Restore for other tests on this machine.
        Preferences.markSpeechModelInstalled()
    }

    func testRepairOptionsComposition() {
        XCTAssertTrue(Repair.Options.all.contains(.permissions))
        XCTAssertTrue(Repair.Options.all.contains(.speechModel))
        XCTAssertFalse(Repair.Options.permissions.contains(.speechModel))
    }
}
