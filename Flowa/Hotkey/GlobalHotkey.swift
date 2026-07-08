// GlobalHotkey.swift
// Flowa
//
// Detect the Fn key globally via CGEventTap and treat each press as a
// toggle: the first press starts recording, the next press commits.
// The listening-state hooks drive FloatingPanel show/hide.

import Foundation
import AppKit
import SwiftUI

@MainActor
final class GlobalHotkey: ObservableObject {

    @Published var isAuthorized: Bool = false
    @Published var isListening:  Bool = false

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
            startListening()
        }
    }

    private func handleFnReleased() {
        // Just clear the down-time so the next press is recognised as a
        // fresh key-down edge. All logic runs on press, not release.
        fnDownTime = nil
    }

    // MARK: - Listening commands

    private func startListening() {
        guard !isListening else { return }
        // Only show the recording UI (isListening + panel) if audio
        // actually starts. This prevents the Flow Bar from appearing
        // for a dictation that will immediately fail (Issue 6).
        if pipeline.start() {
            isListening = true
            panel.show()
        } else {
            // Failure: pipeline already set lastErrorMessage.
            // UI state remains clean; HomeView banner will surface the error
            // when the main window is visible.
            recordMode = .none
        }
    }

    func commitListening() {
        guard isListening else { return }
        isListening = false
        recordMode = .none
        panel.hide()
        pipeline.commit()   // → transcribe → paste into focused app
    }

    func cancelListening() {
        guard isListening else { return }
        isListening = false
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
