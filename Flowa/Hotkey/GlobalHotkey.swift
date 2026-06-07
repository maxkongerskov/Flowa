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

    // Gesture model — intentionally minimal:
    //   1st Fn press  → start recording (pill shows, audio rolling)
    //   2nd Fn press  → commit, transcribe, paste
    //   X on pill     → cancel
    // No hold vs tap distinction, no timing windows. Holding the key
    // longer changes nothing — only presses matter.

    // State
    private var eventTap: CFMachPort?
    // Mirror of eventTap that the nonisolated callback can read without
    // hopping to MainActor. Set in start() and never reassigned, so the
    // unchecked read on the event-tap thread is safe.
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

        print("[Flowa] Fn hotkey ready — hold or double-tap to dictate.")
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

    private func handleFnPressed() {
        // Mark Fn as down so handleFlags' edge detection works.
        fnDownTime = Date()

        // Already recording? This press is the user telling us to stop.
        if isListening {
            print("[Flowa] Fn press → COMMIT")
            commitListening()
            return
        }
        print("[Flowa] Fn press → START recording")

        // Fresh start. Capture the frontmost app (skipping Flowa
        // itself) so the synthetic Cmd+V re-activates the right window
        // even if focus drifts during transcription.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ourBundle = Bundle.main.bundleIdentifier
        if frontmost?.bundleIdentifier != ourBundle {
            pipeline.targetApp = frontmost
        } else {
            pipeline.targetApp = nil   // clipboard-only fallback
        }
        startListening(persistent: true)
    }

    private func handleFnReleased() {
        // Clear the down-marker so the next press is detected as an
        // edge by handleFlags. Releases never affect recording state.
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
        panel.hide()
        pipeline.commit()   // → transcribe → paste into focused app
    }

    func cancelListening() {
        guard isListening else { return }
        isListening = false
        isInRecordMode = false
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
