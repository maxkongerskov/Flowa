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

    func testLooksCompleteRequiresConfigEncoderAndWeights() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowa-model-complete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(SpeechModelStore.looksComplete(root))

        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json"))
        XCTAssertFalse(SpeechModelStore.looksComplete(root))

        let encoder = root.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
        XCTAssertFalse(SpeechModelStore.looksComplete(root), "needs weights")

        let weightsDir = encoder.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        // Tiny file must fail the size floor.
        try Data(repeating: 0, count: 64).write(to: weightsDir.appendingPathComponent("weight.bin"))
        XCTAssertFalse(SpeechModelStore.looksComplete(root), "tiny weights incomplete")
    }

    func testResolveReturnsNilForIncompleteBundle() {
        let resolved = SpeechModelStore.resolveLocalModelFolder(
            bundledPath: "/tmp/flowa-does-not-exist-\(UUID().uuidString)"
        )
        if let resolved {
            XCTAssertTrue(
                SpeechModelStore.looksComplete(URL(fileURLWithPath: resolved, isDirectory: true)),
                "resolve must only return complete folders"
            )
        }
    }

    func testRepairResetSpeechModelClearsFirstRunFlag() {
        Preferences.markSpeechModelInstalled()
        XCTAssertTrue(Preferences.speechModelInstalled)

        Repair.resetSpeechModelInstall(clearCache: false)
        XCTAssertFalse(Preferences.speechModelInstalled)

        Preferences.markSpeechModelInstalled()
    }

    func testRepairOptionsComposition() {
        XCTAssertTrue(Repair.Options.all.contains(.permissions))
        XCTAssertTrue(Repair.Options.all.contains(.speechModel))
        XCTAssertFalse(Repair.Options.permissions.contains(.speechModel))
    }
}
