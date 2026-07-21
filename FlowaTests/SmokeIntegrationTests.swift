import XCTest
import AVFoundation
import AppKit
@testable import Flowa

/// Live smoke paths that exercise shipped types on this Mac.
@MainActor
final class SmokeIntegrationTests: XCTestCase {

    func testPipelineStartCancelStartAgain_freshEnginePath() throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "Microphone not authorized for test host (status=\(mic.rawValue))")

        let pipeline = DictationPipeline()
        let ok1 = pipeline.start(targetApp: nil, microphoneUID: "default")
        XCTAssertTrue(ok1, "first start should succeed when mic authorized; error=\(pipeline.lastErrorMessage ?? "nil")")
        XCTAssertTrue(pipeline.audio.isRecording)
        pipeline.cancel()
        XCTAssertFalse(pipeline.audio.isRecording)

        // Second session — fresh AVAudioEngine path (macOS 26 second-recording crash class)
        let ok2 = pipeline.start(targetApp: nil, microphoneUID: "default")
        XCTAssertTrue(ok2, "second start should succeed; error=\(pipeline.lastErrorMessage ?? "nil")")
        XCTAssertTrue(pipeline.audio.isRecording)
        pipeline.cancel()
        XCTAssertFalse(pipeline.audio.isRecording)
    }

    func testPipelineStartWithPreferredMicUID() throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "Microphone not authorized for test host")

        let pipeline = DictationPipeline()
        let uid = Preferences.microphoneUID
        let ok = pipeline.start(targetApp: nil, microphoneUID: uid)
        XCTAssertTrue(ok, "start with Preferences.microphoneUID=\(uid) failed: \(pipeline.lastErrorMessage ?? "nil")")
        XCTAssertTrue(pipeline.audio.isRecording)
        pipeline.cancel()
    }

    func testCommitStopsRecordingWithoutHangingOnEmptyCapture() async throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "Microphone not authorized for test host")

        let pipeline = DictationPipeline()
        let ok = pipeline.start(targetApp: nil, microphoneUID: "default")
        XCTAssertTrue(ok)
        // Brief capture; silence may yield nil transcription — that is OK.
        try await Task.sleep(nanoseconds: 350_000_000)
        pipeline.commit(language: "en")
        XCTAssertFalse(pipeline.audio.isRecording, "commit must stop capture immediately")
        // Do not await full Whisper load/transcribe here (can download/compile for minutes).
    }

    func testGlobalHotkeySessionStartsIdleAndAcceptsInjectedPipeline() {
        let pipeline = DictationPipeline()
        let hotkey = GlobalHotkey(pipeline: pipeline)
        XCTAssertEqual(hotkey.session, .idle)
        XCTAssertFalse(hotkey.isListening)
        XCTAssertTrue(hotkey.pipeline === pipeline)
    }

    func testLanguageAndMicPreferencesRoundTripForCallers() {
        let defaults = UserDefaults.standard
        let langKey = PrefKey.language
        let micKey = PrefKey.microphone
        let oldLang = defaults.string(forKey: langKey)
        let oldMic = defaults.string(forKey: micKey)
        defer {
            if let oldLang { defaults.set(oldLang, forKey: langKey) } else { defaults.removeObject(forKey: langKey) }
            if let oldMic { defaults.set(oldMic, forKey: micKey) } else { defaults.removeObject(forKey: micKey) }
        }

        defaults.set("da", forKey: langKey)
        defaults.set("default", forKey: micKey)
        XCTAssertEqual(Preferences.languageCode, "da")
        XCTAssertEqual(Preferences.languageForWhisper, "da")
        XCTAssertEqual(Preferences.microphoneUID, "default")
        XCTAssertTrue(Preferences.isSystemDefaultMicrophone(Preferences.microphoneUID))

        defaults.set("auto", forKey: langKey)
        XCTAssertNil(Preferences.languageForWhisper)

        defaults.set("en", forKey: langKey)
        XCTAssertEqual(LanguageOption.displayName(for: Preferences.languageCode), "English")
    }

    func testAudioDeviceManagerListsInputsWithoutCrash() {
        let devices = AudioDeviceManager.listInputs()
        XCTAssertGreaterThanOrEqual(devices.count, 0)
        for d in devices {
            XCTAssertFalse(d.uid.isEmpty)
            XCTAssertFalse(d.name.isEmpty)
        }
        // Prefer at least one input on a real Mac with a mic
        if devices.isEmpty {
            print("[smoke] WARN: no audio input devices listed")
        } else {
            print("[smoke] inputs: \(devices.map(\.name).joined(separator: ", "))")
        }
    }

    func testRepairSpawnedHelperSurvivesParentExit() throws {
        // Short-lived Python parent starts the exact shipped relaunch argv in a new
        // session (start_new_session=True ≈ setsid), prints pid, exits immediately.
        // This models NSApp.terminate leaving the helper alive.
        let path = "/Applications/Flowa-Smoke-Nonexistent.app"
        let cmd = Repair.relaunchCommand(bundlePath: path, delaySeconds: 60)
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // JSON-encode argv so path/spaces never hit a shell.
        let payload: [String: Any] = [
            "executable": cmd.executable,
            "arguments": cmd.arguments
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let jsonStr = String(data: json, encoding: .utf8)!
        parent.arguments = [
            "-c",
            """
            import json, subprocess, sys
            spec = json.loads(sys.argv[1])
            p = subprocess.Popen(
                [spec["executable"]] + spec["arguments"],
                start_new_session=True,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            print(p.pid)
            sys.exit(0)
            """,
            jsonStr
        ]
        let pipe = Pipe()
        parent.standardOutput = pipe
        parent.standardError = Pipe()
        try parent.run()
        parent.waitUntilExit()
        XCTAssertEqual(parent.terminationStatus, 0, "parent launcher should exit immediately")

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pidStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let pid = Int32(pidStr) else {
            XCTFail("could not parse helper pid from: \(pidStr)")
            return
        }
        // Parent already gone; helper must still be alive.
        XCTAssertTrue(kill(pid, 0) == 0, "relaunch helper pid \(pid) should survive parent exit")
        kill(pid, SIGTERM)

        // Also exercise shipped spawn API itself
        guard let live = Repair.spawnDetachedRelaunch(bundlePath: path, delaySeconds: 60) else {
            XCTFail("spawnDetachedRelaunch returned nil")
            return
        }
        XCTAssertTrue(live.isRunning)
        live.terminate()
        live.waitUntilExit()
    }
}
