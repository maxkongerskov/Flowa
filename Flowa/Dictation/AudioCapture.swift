// AudioCapture.swift
// Flowa
//
// AVAudioEngine-based microphone capture. Records Float samples into
// an in-memory buffer at 16 kHz mono (the format WhisperKit wants),
// publishes a live RMS level for the Flow Bar waveform, and on stop
// writes the buffer to a temporary 16-bit PCM WAV file ready for
// transcription.
//
// Why not stream into WhisperKit live: streaming inference is more
// fragile and the perceived UX win is small for short dictations
// (<20s). The file-based path is chosen for reliability; streaming can
// be revisited if the wait time ever becomes real friction.

import Foundation
@preconcurrency import AVFoundation
import CoreAudio
import Combine

// MARK: - Audio input device enumeration
//
// Tiny Core Audio wrapper used by the Microphone picker on Home and
// by AudioCapture.start() to override the AVAudioEngine input. We
// persist the device's stable UID (not its dynamic AudioDeviceID,
// which changes across reboots / hotplug) and resolve it back to a
// live AudioDeviceID at recording time.

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioDeviceManager {

    /// Returns every audio device that exposes at least one input
    /// stream, in the order Core Audio gives them. The default system
    /// input is included; pick it by name if you want a "default" pin.
    static func listInputs() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var devices: [AudioInputDevice] = []
        for id in ids {
            if hasInputStream(id), let uid = deviceUID(id) {
                devices.append(AudioInputDevice(id: id, uid: uid, name: deviceName(id)))
            }
        }
        return devices
    }

    /// Resolve a persisted UID back to a live AudioDeviceID. nil if the
    /// device has been unplugged since the user selected it.
    static func find(uid: String) -> AudioInputDevice? {
        listInputs().first { $0.uid == uid }
    }

    // MARK: - Per-device property reads

    private static func hasInputStream(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return size > 0
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        return copyCFString(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        return copyCFString(id, selector: kAudioObjectPropertyName) ?? "Device \(id)"
    }

    /// Read a CFString property via Core Audio safely. We pass an
    /// `Unmanaged<CFString>?` (a pointer-sized value) instead of a
    /// `CFString` variable — `&cfString` is incorrect because CFString
    /// holds an object reference, and the compiler now warns about it.
    private static func copyCFString(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &unmanaged)
        guard err == noErr, let cf = unmanaged?.takeRetainedValue() else { return nil }
        return cf as String
    }
}

@MainActor
final class AudioCapture: ObservableObject {

    /// 0...1, RMS-derived volume for the Flow Bar's waveform. Updated
    /// every audio buffer (~50 Hz at 1024-frame buffer size).
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?

    // var (not let) so we can replace it with a fresh instance each
    // recording session. macOS 26 has stricter AVFAudio tap-state
    // tracking — even after removeTap+stop, the old engine's internal
    // tap registry can survive, causing an NSException on the next
    // installTap that Swift cannot catch. Creating a brand-new engine
    // each time guarantees a clean slate at the cost of a tiny alloc.
    private var engine = AVAudioEngine()
    private var collected: [Float] = []
    private let targetSampleRate: Double = 16_000
    // converter is set on MainActor during start() and only read on the
    // audio thread inside processBuffer (nonisolated). The set-then-read
    // ordering means there's no data race in practice — mark it
    // nonisolated(unsafe) so Swift 6 lets the audio thread read it.
    private nonisolated(unsafe) var converter: AVAudioConverter?

    // MARK: - Public lifecycle

    func start() throws {
        guard !isRecording else { return }
        collected.removeAll(keepingCapacity: true)
        lastError = nil

        // Replace the engine with a fresh instance every session.
        // This is the definitive fix for the "nullptr == Tap()" NSException
        // that occurs on the second+ recording session on macOS 26.
        // removeTap alone is not sufficient — AVFAudio's internal tap state
        // persists on the old engine object even after stop()+removeTap().
        // A new AVAudioEngine is cheap to allocate and guaranteed clean.
        engine = AVAudioEngine()

        let input = engine.inputNode

        // Apply the user's preferred input device if they picked a
        // specific one in the UI. "default" / unset → leave the engine
        // routed to the system default mic.
        let preferred = UserDefaults.standard.string(forKey: "flowa.microphone") ?? "default"
        if preferred != "default", let device = AudioDeviceManager.find(uid: preferred) {
            var deviceID = device.id
            if let au = input.audioUnit {
                let err = AudioUnitSetProperty(
                    au,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if err != noErr {
                    print("[Flowa][audio] could not switch input to \(device.name): err=\(err) — falling back to system default")
                }
            }
        }

        let nativeFormat = input.outputFormat(forBus: 0)

        // Defensive: macOS sometimes returns a degenerate (0 sr / 0 ch)
        // format from inputNode before the engine starts. Bail loudly
        // so the failure shows up in logs instead of producing silence.
        if nativeFormat.sampleRate == 0 || nativeFormat.channelCount == 0 {
            throw NSError(domain: "AudioCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Input node returned an invalid format (sr=\(nativeFormat.sampleRate), ch=\(nativeFormat.channelCount)). Check that the system default input device is reachable."])
        }

        // Build a converter from native input → 16 kHz mono Float32
        // (WhisperKit's expected canonical format before WAV write).
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not build target format"])
        }
        converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        if converter == nil {
            throw NSError(domain: "AudioCapture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioConverter init returned nil for \(nativeFormat) → \(targetFormat)"])
        }

        // Always removeTap before installTap — removeTap is a no-op if no
        // tap is installed, so this is always safe. Skipping this causes an
        // unrecoverable NSException crash on the second recording session.
        // See: https://github.com/rxlabz/speech_recognition/pull/34
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buf, _ in
            guard let self else { return }
            guard let (samples, level) = self.processBuffer(buf) else { return }
            Task { @MainActor [weak self] in
                self?.append(samples: samples, level: level)
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        return writeWAV()
    }

    func cancel() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        collected.removeAll(keepingCapacity: false)
    }

    // MARK: - Buffer handling
    //
    // processBuffer runs on the audio thread and returns Sendable
    // values (a fresh [Float] copy + a Float level). Nothing about
    // the AVAudioPCMBuffer escapes — this is what makes the Swift 6
    // concurrency checker happy.
    nonisolated private func processBuffer(_ inBuf: AVAudioPCMBuffer) -> ([Float], Float)? {
        guard let converter else { return nil }

        let ratio = targetSampleRate / inBuf.format.sampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 64)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: targetSampleRate,
                                             channels: 1, interleaved: false),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrameCapacity)
        else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outBuf, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuf
        }

        guard error == nil,
              let channel = outBuf.floatChannelData?[0]
        else { return nil }

        let n = Int(outBuf.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: n))

        var sumSq: Float = 0
        for s in samples { sumSq += s * s }
        let rms = sqrt(sumSq / Float(max(n, 1)))
        let level = min(Float(1.0), rms * 6.5)
        return (samples, level)
    }

    /// MainActor-isolated helper called from the audio-tap closure once
    /// the buffer has been converted into Sendable values.
    private func append(samples: [Float], level newLevel: Float) {
        collected.append(contentsOf: samples)
        // Light smoothing so the waveform isn't jittery.
        self.level = self.level * 0.5 + newLevel * 0.5
    }

    // MARK: - WAV writing
    //
    // Hand-rolled 16-bit PCM WAV. Could use AVAudioFile but for a
    // one-shot temp file the header is 44 bytes and writing it
    // manually avoids file-format negotiation overhead.

    private func writeWAV() -> URL? {
        guard !collected.isEmpty else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flowa-\(UUID().uuidString.prefix(8)).wav")

        let sampleCount = collected.count
        let byteRate = Int(targetSampleRate) * 2 // 16-bit mono
        let dataSize = sampleCount * 2
        let fileSize = 36 + dataSize

        var data = Data(capacity: 44 + dataSize)
        func writeAscii(_ s: String) { data.append(contentsOf: s.utf8) }
        func writeLE32(_ v: Int) {
            var v = UInt32(v).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func writeLE16(_ v: Int) {
            var v = UInt16(v).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        writeAscii("RIFF")
        writeLE32(fileSize)
        writeAscii("WAVE")
        writeAscii("fmt ")
        writeLE32(16)            // PCM chunk size
        writeLE16(1)             // PCM format
        writeLE16(1)             // mono
        writeLE32(Int(targetSampleRate))
        writeLE32(byteRate)
        writeLE16(2)             // block align
        writeLE16(16)            // bits per sample
        writeAscii("data")
        writeLE32(dataSize)

        // Float samples → Int16 PCM
        for sample in collected {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767.0)
            var le = int16.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
