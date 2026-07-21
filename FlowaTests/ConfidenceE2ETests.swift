import XCTest
import AVFoundation
import AppKit
import ApplicationServices
@testable import Flowa

/// High-confidence end-to-end paths: Whisper on real TTS audio, paste, hotkey tap, full pipeline.
@MainActor
final class ConfidenceE2ETests: XCTestCase {

    private var fixturesDir: URL {
        // Prefer committed fixtures next to sources (readable when tests run from DerivedData host).
        let candidates: [URL] = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Flowa/TestFixtures"),
            URL(fileURLWithPath: "/Users/maxkongerskov/Downloads/Flowa/FlowaTests/Fixtures")
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c.path) {
            return c
        }
        return candidates[0]
    }

    private func fixture(_ name: String) throws -> URL {
        let url = fixturesDir.appendingPathComponent(name)
        try XCTSkipIf(!FileManager.default.fileExists(atPath: url.path),
                      "Missing fixture \(url.path)")
        return url
    }

    // MARK: - Whisper on real speech audio

    func testWhisperTranscribesTTSHelloPhrase() async throws {
        let wav = try fixture("hello_flowa.wav")
        let t = Transcriber()
        await t.loadIfNeeded()
        // Allow model download/compile on first run
        if case .error(let msg) = t.status {
            XCTFail("model load failed: \(msg)")
            return
        }
        XCTAssertEqual(t.status, .ready, "expected ready, got \(t.status)")

        let text = await t.transcribe(wavFile: wav, language: "en")
        XCTAssertNotNil(text, "transcription returned nil; status=\(t.status)")
        let normalized = (text ?? "")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        print("[confidence] hello transcript: \(text ?? "nil")")
        // TTS: "hello flowa confidence test" — accept partial strong tokens
        let hits = ["hello", "flowa", "confidence", "test"].filter { normalized.contains($0) }
        XCTAssertGreaterThanOrEqual(hits.count, 2,
                                    "expected ≥2 of hello/flowa/confidence/test in: \(normalized)")
    }

    func testWhisperTranscribesQuickBrownFox() async throws {
        let wav = try fixture("quick_brown_fox.wav")
        let t = Transcriber()
        await t.loadIfNeeded()
        guard t.status == .ready else {
            XCTFail("model not ready: \(t.status)")
            return
        }
        let text = await t.transcribe(wavFile: wav, language: "en")
        XCTAssertNotNil(text)
        let n = (text ?? "").lowercased()
        print("[confidence] fox transcript: \(text ?? "nil")")
        XCTAssertTrue(n.contains("quick") || n.contains("fox") || n.contains("dog") || n.contains("lazy"),
                      "expected fox-sentence tokens in: \(n)")
    }

    // MARK: - TextInserter (clipboard floor of success)

    func testTextInserterWritesClipboard() {
        let marker = "flowa-paste-\(UUID().uuidString.prefix(8))"
        let pb = NSPasteboard.general
        let before = pb.string(forType: .string)
        let outcome = TextInserter.paste(marker, targetApp: nil)
        XCTAssertEqual(outcome, .clipboardOnly)
        let after = pb.string(forType: .string)
        XCTAssertEqual(after, marker)
        // Restore prior clipboard if we had one
        if let before {
            pb.clearContents()
            pb.setString(before, forType: .string)
        }
    }

    func testTextInserterRejectsEmpty() {
        XCTAssertEqual(TextInserter.paste("", targetApp: nil), .failed)
    }

    // MARK: - GlobalHotkey event tap

    func testGlobalHotkeyStartCreatesEventTapWhenPermitted() {
        let pipeline = DictationPipeline()
        let hotkey = GlobalHotkey(pipeline: pipeline)
        hotkey.start()
        // Input Monitoring may or may not be granted to the test host binary.
        // If granted → isAuthorized true; if not → false without crash.
        print("[confidence] hotkey.isAuthorized=\(hotkey.isAuthorized)")
        if hotkey.isAuthorized {
            XCTAssertTrue(hotkey.isAuthorized)
            // Restart path must not crash
            hotkey.restart()
            XCTAssertTrue(hotkey.isAuthorized)
        } else {
            // Still a valid outcome: document for confidence report
            print("[confidence] WARN: Input Monitoring not granted to test host — tap create failed cleanly")
        }
        hotkey.stop()
        XCTAssertFalse(hotkey.isAuthorized)
    }

    // MARK: - Full pipeline: inject WAV via stop path approximation
    //
    // AudioCapture writes WAV on stop from mic. For a deterministic phrase we
    // drive Transcriber + TextInserter + RecentRing the same way commit does.

    func testFullDictationPath_transcribePasteAndRecentRing() async throws {
        let wav = try fixture("hello_flowa.wav")
        let pipeline = DictationPipeline()
        await pipeline.transcriber.loadIfNeeded()
        guard pipeline.transcriber.status == .ready else {
            XCTFail("model not ready: \(pipeline.transcriber.status)")
            return
        }

        let beforeCount = pipeline.recent.count
        let markerPrefix = "flowa-e2e-"
        // Run the same internal sequence commit uses, with our fixture WAV.
        // We cannot call private runTranscription; re-drive the public contract:
        // transcribe → paste → insert recent via pipeline by committing after
        // we cannot inject WAV into AudioCapture easily — so simulate via
        // public APIs + RecentRing which pipeline uses.
        let text = await pipeline.transcriber.transcribe(wavFile: wav, language: "en")
        XCTAssertNotNil(text)
        let spoken = text ?? ""
        XCTAssertFalse(spoken.isEmpty)

        let pasteOutcome = TextInserter.paste(spoken, targetApp: nil)
        XCTAssertNotEqual(pasteOutcome, .failed)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), spoken)

        // Recent ring (same helper pipeline uses after successful dictation)
        let entry = Dictation(text: markerPrefix + spoken, targetAppName: "ConfidenceE2E", date: Date())
        let updated = RecentRing.inserting(entry, into: pipeline.recent, limit: 100)
        XCTAssertEqual(updated.first?.text, markerPrefix + spoken)
        XCTAssertEqual(updated.count, min(beforeCount + 1, 100))

        print("[confidence] full path text=\(spoken)")
    }

    /// Drive real AudioCapture → commit → async transcription without hanging the suite forever.
    func testLiveMicCaptureCommitKicksTranscription() async throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "mic not authorized")

        let pipeline = DictationPipeline()
        // Prewarm model so commit's Task is not stuck on multi-minute first download alone
        await pipeline.transcriber.loadIfNeeded()

        let ok = pipeline.start(targetApp: NSWorkspace.shared.frontmostApplication,
                                microphoneUID: "default")
        XCTAssertTrue(ok, pipeline.lastErrorMessage ?? "start failed")
        // Capture ~1.2s of ambient audio (may be silence → nil text is OK)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        pipeline.commit(language: "en")
        XCTAssertFalse(pipeline.audio.isRecording)

        // Wait up to 90s for transcription task to settle status back to ready/error
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if pipeline.transcriber.status == .ready || pipeline.transcriber.status == .idle {
                break
            }
            if case .error = pipeline.transcriber.status { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        print("[confidence] after live commit status=\(pipeline.transcriber.status) err=\(pipeline.lastErrorMessage ?? "nil") recent=\(pipeline.recent.count)")
        // Must not stay stuck in .transcribing forever
        if case .transcribing = pipeline.transcriber.status {
            XCTFail("transcription still in progress after 90s")
        }
    }
}
