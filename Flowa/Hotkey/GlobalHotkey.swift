// GlobalHotkey.swift
// Flowa
//
// Detect the Fn key globally via CGEventTap and treat each press as a
// toggle: first press starts recording, next press commits.
// Owns the floating panel only — DictationPipeline is injected from the app.

import Foundation
import AppKit
import SwiftUI

@MainActor
final class GlobalHotkey: ObservableObject {

    /// Single recording session state (replaces dual recordMode + isListening).
    enum Session: Equatable {
        case idle
        case recording
    }

    @Published var isAuthorized: Bool = false
    @Published private(set) var session: Session = .idle

    /// Convenience for UI that only needs a boolean.
    var isListening: Bool { session == .recording }

    /// Injected domain pipeline — not owned here.
    let pipeline: DictationPipeline

    private var eventTap: CFMachPort?
    nonisolated(unsafe) fileprivate var eventTapUnsafe: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDownTime: Date?

    private lazy var panel: FlowaFloatingPanel = {
        let audioRef = pipeline.audio
        return FlowaFloatingPanel {
            FlowBarContent(
                audio: audioRef,
                onCancel: { [weak self] in
                    Task { @MainActor in self?.cancelListening() }
                },
                onCommit: { [weak self] in
                    Task { @MainActor in self?.commitListening() }
                }
            )
        }
    }()

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Lifecycle

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        eventTapUnsafe = nil
        runLoopSource = nil
        isAuthorized = false
    }

    func restart() {
        stop()
        start()
    }

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.eventTapUnsafe {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            DispatchQueue.main.async { me.handleFlags(flags) }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: opaqueSelf
        ) else {
            print("[Flowa] CGEvent.tapCreate FAILED — Input Monitoring permission missing?")
            isAuthorized = false
            return
        }

        print("[Flowa] Fn hotkey ready — tap to start/stop dictation.")
        eventTap = tap
        eventTapUnsafe = tap
        isAuthorized = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoopSource = source
    }

    // MARK: - State machine

    private func handleFlags(_ flags: CGEventFlags) {
        let fnNow = flags.contains(.maskSecondaryFn)
        let fnWas = (fnDownTime != nil)
        if fnNow && !fnWas { handleFnPressed() }
        else if !fnNow && fnWas { handleFnReleased() }
    }

    private func frontmostTargetApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ourBundle = Bundle.main.bundleIdentifier
        return (frontmost?.bundleIdentifier != ourBundle) ? frontmost : nil
    }

    private func handleFnPressed() {
        guard fnDownTime == nil else { return }
        fnDownTime = Date()

        switch session {
        case .recording:
            print("[Flowa] Fn press → COMMIT")
            commitListening()
        case .idle:
            print("[Flowa] Fn press → START recording")
            startListening()
        }
    }

    private func handleFnReleased() {
        fnDownTime = nil
    }

    // MARK: - Listening commands

    private func startListening() {
        guard session == .idle else { return }

        // Don't capture audio if Whisper isn't ready — user would record
        // successfully then get silence in Recent. Kick install/repair UI.
        if !pipeline.transcriber.isReady {
            print("[Flowa] Fn press ignored — speech model not ready (\(pipeline.transcriber.status))")
            pipeline.surfaceModelNotReady()
            NotificationCenter.default.post(name: .flowaShowMainWindow, object: nil)
            Task { await pipeline.transcriber.loadIfNeeded() }
            return
        }

        let target = frontmostTargetApp()
        let micUID = AudioDeviceManager.resolveCaptureUID(Preferences.microphoneUID)
        if pipeline.start(targetApp: target, microphoneUID: micUID) {
            session = .recording
            panel.show()
        }
        // On failure pipeline already set lastErrorMessage; stay idle.
    }

    func commitListening() {
        guard session == .recording else { return }
        session = .idle
        panel.hide()
        pipeline.commit(language: Preferences.languageForWhisper)
    }

    func cancelListening() {
        guard session == .recording else { return }
        session = .idle
        fnDownTime = nil
        panel.hide()
        pipeline.cancel()
    }
}
