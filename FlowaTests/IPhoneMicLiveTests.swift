import XCTest
@testable import Flowa

@MainActor
final class IPhoneMicLiveTests: XCTestCase {
    func testWhisperTranscribesLiveIPhoneRecording() async throws {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/iphone_live_speak.wav"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Flowa/TestFixtures/iphone_live_speak.wav"),
        ]
        guard let wav = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            XCTFail("missing iphone_live_speak.wav fixture")
            return
        }
        let t = Transcriber()
        await t.loadIfNeeded()
        XCTAssertEqual(t.status, .ready, "\(t.status)")
        let text = await t.transcribe(wavFile: wav, language: "en")
        print("[iphone-live] transcript: \(text ?? "nil")")
        XCTAssertNotNil(text)
        XCTAssertFalse((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "expected non-empty transcript from live iPhone speech")
    }
}
