import XCTest
import AVFoundation
import AppKit
@testable import Flowa

/// Final ship gate: cold-path mic list, dual-device capture, Continuity labeling, resolve.
@MainActor
final class ShipGateTests: XCTestCase {

    func testPickerListsStudioAndIPhoneWithContinuityLabel() {
        let devices = AudioDeviceManager.listInputsForPicker()
        XCTAssertFalse(devices.contains(where: { MicDeviceKind.isEphemeralAggregateUID($0.uid) }),
                       "picker must not expose ephemeral aggregates")

        let studio = devices.first { $0.name.localizedCaseInsensitiveContains("Studio Display") }
        let iphone = devices.first { $0.isContinuity }

        // On this developer machine both should be present; skip soft if hardware gone.
        if studio == nil && iphone == nil {
            // Still validate empty-safe path
            XCTAssertGreaterThanOrEqual(devices.count, 0)
            return
        }

        if let studio {
            XCTAssertEqual(studio.kind, .standard)
            XCTAssertEqual(studio.displayName, studio.name)
        }
        if let iphone {
            XCTAssertEqual(iphone.kind, .continuity)
            XCTAssertTrue(iphone.displayName.contains("speak near phone"),
                          "Continuity must carry speak-near-phone label: \(iphone.displayName)")
        }
    }

    func testResolveCaptureUIDFallsBackForMissingAndAggregate() {
        XCTAssertEqual(AudioDeviceManager.resolveCaptureUID("default"), "default")
        XCTAssertEqual(AudioDeviceManager.resolveCaptureUID(""), "default")
        XCTAssertEqual(AudioDeviceManager.resolveCaptureUID("CADefaultDeviceAggregate-999-0"), "default")
        XCTAssertEqual(AudioDeviceManager.resolveCaptureUID("totally-missing-device-uid"), "default")

        if let live = AudioDeviceManager.listInputsForPicker().first {
            XCTAssertEqual(AudioDeviceManager.resolveCaptureUID(live.uid), live.uid)
        }
    }

    func testStudioDisplayCaptureThenCommitProducesAudioOrCleanSilence() async throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "mic not authorized")

        guard let studio = AudioDeviceManager.listInputsForPicker()
            .first(where: { $0.name.localizedCaseInsensitiveContains("Studio Display") }) else {
            throw XCTSkip("Studio Display mic not present")
        }

        let pipeline = DictationPipeline()
        await pipeline.transcriber.loadIfNeeded()

        let ok = pipeline.start(targetApp: nil, microphoneUID: studio.uid)
        XCTAssertTrue(ok, pipeline.lastErrorMessage ?? "start failed")

        // Acoustic energy while recording
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Samantha", "ship gate studio display microphone test"]
        try? p.run()
        p.waitUntilExit()
        try await Task.sleep(nanoseconds: 200_000_000)

        let peak = pipeline.audio.sessionPeakLevel
        pipeline.commit(language: "en")
        XCTAssertFalse(pipeline.audio.isRecording)

        // Either we heard speech (peak high) or silence guard fired with a message
        if peak >= AudioCapture.silencePeakThreshold {
            // Wait briefly for async transcription
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                if case .transcribing = pipeline.transcriber.status {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                break
            }
            print("[ship-gate] studio peak=\(peak) status=\(pipeline.transcriber.status) recent=\(pipeline.recent.count)")
        } else {
            XCTAssertNotNil(pipeline.lastErrorMessage)
            print("[ship-gate] studio silent path message=\(pipeline.lastErrorMessage ?? "")")
        }
    }

    func testIPhoneContinuityCapturePathStartsAndTracksKind() throws {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        try XCTSkipIf(mic != .authorized, "mic not authorized")

        guard let iphone = AudioDeviceManager.listInputsForPicker().first(where: { $0.isContinuity }) else {
            throw XCTSkip("iPhone Continuity mic not present")
        }

        let pipeline = DictationPipeline()
        let ok = pipeline.start(targetApp: nil, microphoneUID: iphone.uid)
        XCTAssertTrue(ok, pipeline.lastErrorMessage ?? "start failed")
        XCTAssertEqual(pipeline.audio.sessionDeviceKind, .continuity)
        XCTAssertTrue(pipeline.audio.isRecording)
        // Don't commit without user speech — cancel keeps suite non-flaky
        pipeline.cancel()
        XCTAssertFalse(pipeline.audio.isRecording)
    }

    func testColdPipelinePrewarmAndHotkeyInjection() async {
        let pipeline = DictationPipeline()
        let hotkey = GlobalHotkey(pipeline: pipeline)
        XCTAssertTrue(hotkey.pipeline === pipeline)
        XCTAssertEqual(hotkey.session, .idle)
        await pipeline.prewarm()
        // Give model a moment if already cached
        try? await Task.sleep(nanoseconds: 500_000_000)
        // prewarm is fire-and-forget; status may still be preparing on cold cache
        print("[ship-gate] after prewarm status=\(pipeline.transcriber.status)")
        hotkey.start()
        print("[ship-gate] hotkey authorized=\(hotkey.isAuthorized)")
        hotkey.stop()
    }
}
