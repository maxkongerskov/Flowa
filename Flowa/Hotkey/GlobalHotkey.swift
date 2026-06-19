// GlobalHotkey.swift
// Flowa
//
// Detect the Fn key globally via CGEventTap and classify each interaction
// as HOLD, SINGLE_TAP, or DOUBLE_TAP. Ported from Vani Spike 1 with the
// listening-state hooks driving FloatingPanel show/hide.

import Foundation
import AppKit
import SwiftUI

@MainActor
final class GlobalHotkey: ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var isListening:  Bool = false
    @Published var isInRecordMode: Bool = false

    /// Owned pipeline — audio capture, Whisper transcription, paste.
    /// Public so views (and the Flow Bar) can bind to its published
    /// audio level for the live waveform.
    let pipeline = DictationPipeline()

    // Gesture model:
    //
    //   TAP (any press + release):
    //     → if not recording: show bar, start recording.
    //     → if recording: commit, transcribe, paste.
    //
    //   X on pill → cancel.

    // Recording mode
    private enum RecordMode { case none, toggle }
    private var recordMode: RecordMode = .none

    // State
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

    // MARK: - Lifecycle

    /// Tear down the event tap so a subsequent `start()` rebuilds it
    /// against the current TCC permission state. Used when Input
    /// Monitoring is granted *after* launch — the old tap stays dead
    /// even though permissions are now correct.
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

    /// Convenience: stop + start. Call after granting Input Monitoring
    /// or Accessibility from System Settings so the hotkey actually
    /// becomes live without quitting the app.
    func restart() {
        stop()
        start()
    }

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            // First-line tracer: confirms the tap callback is alive
            // and receiving events. If we never see this even when
            // pressing Fn, Input Monitoring is silently denied.
            print("[Flowa][tap] event type=\(type.rawValue)")
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Re-enable synchronously on the event-tap thread so the
                // next Fn event doesn't fall on the floor while we wait
                // for the main queue.
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

    private func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - State machine

    private func handleFlags(_ flags: CGEventFlags) {
        let fnNow = flags.contains(.maskSecondaryFn)
        let fnWas = (fnDownTime != nil)
        if fnNow && !fnWas { handleFnPressed() }
        else if !fnNow && fnWas { handleFnReleased() }
    }

    private func captureFrontmostApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ourBundle = Bundle.main.bundleIdentifier
        pipeline.targetApp = (frontmost?.bundleIdentifier != ourBundle) ? frontmost : nil
    }

    private func handleFnPressed() {
        // Ignore key-repeat events — only act on the first down edge.
        guard fnDownTime == nil else { return }
        fnDownTime = Date()

        switch recordMode {
        case .toggle:
            // Already recording — commit immediately on key-down.
            print("[Flowa] Fn press → COMMIT")
            recordMode = .none
            commitListening()

        case .none:
            // Not recording — capture frontmost app and start immediately.
            captureFrontmostApp()
            print("[Flowa] Fn press → START recording")
            recordMode = .toggle
            startListening(persistent: true)
        }
    }

    private func handleFnReleased() {
        // Just clear the down-time so the next press is recognised as a
        // fresh key-down edge. All logic runs on press, not release.
        fnDownTime = nil
    }

    // MARK: - Listening commands

    private func startListening(persistent: Bool) {
        guard !isListening else { return }
        isListening = true
        isInRecordMode = persistent
        panel.show()
        pipeline.start()
    }

    func commitListening() {
        guard isListening else { return }
        isListening = false
        isInRecordMode = false
        recordMode = .none
        panel.hide()
        pipeline.commit()   // → transcribe → paste into focused app
    }

    func cancelListening() {
        guard isListening else { return }
        isListening = false
        isInRecordMode = false
        recordMode = .none
        fnDownTime = nil
        panel.hide()
        pipeline.cancel()
    }

    // MARK: - Permission helper

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
