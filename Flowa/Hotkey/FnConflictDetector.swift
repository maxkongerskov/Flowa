// FnConflictDetector.swift
// Flowa
//
// System-state detectors + a unified permission manager for the three
// TCC services Flowa needs (Microphone, Input Monitoring, Accessibility)
// plus a Repair flow that resets TCC and re-registers the bundle.
//
//   FnConflictDetector  — Apple's Fn handler hijacking the key.
//   PermissionChecker   — live status of the three TCC permissions.
//   Repair              — tccutil + lsregister + self-relaunch.

import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import IOKit
import IOKit.hid

@MainActor
final class FnConflictDetector: ObservableObject {

    enum Status: Equatable {
        case clean
        case conflict(behavior: AppleFnBehavior)
        case unknown
    }

    enum AppleFnBehavior: Int {
        case doNothing = 0
        case changeInputSource = 1
        case showEmoji = 2
        case startDictation = 3
        var displayName: String {
            switch self {
            case .doNothing:         return "Do Nothing"
            case .changeInputSource: return "Change Input Source"
            case .showEmoji:         return "Show Emoji & Symbols"
            case .startDictation:    return "Start Dictation"
            }
        }
    }

    @Published private(set) var status: Status = .unknown
    private var timer: Timer?

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        guard let raw = defaults?.object(forKey: "AppleFnUsageType") else {
            status = .unknown
            return
        }
        let value: Int?
        if let n = raw as? Int { value = n }
        else if let n = raw as? NSNumber { value = n.intValue }
        else { value = nil }
        guard let v = value, let behavior = AppleFnBehavior(rawValue: v) else {
            status = .unknown
            return
        }
        status = behavior == .doNothing ? .clean : .conflict(behavior: behavior)
    }

    func openKeyboardSettings() {
        for s in [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ] {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - PermissionChecker
//
// Single source of truth for the three TCC permissions Flowa needs.
// Polls on a 2 s timer + on app activation (so granting in System
// Settings is reflected instantly when the user comes back). Exposes
// deep links into the right Settings pane for each, plus a request
// method that triggers the macOS-native prompt where possible.

@MainActor
final class PermissionChecker: ObservableObject {

    @Published private(set) var microphoneGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false
    @Published private(set) var accessibilityGranted: Bool = false

    /// Bumped on every transition, so views observing it can rebuild
    /// downstream state (e.g. the CGEventTap after IM is granted).
    @Published private(set) var changeStamp: Int = 0

    var allGranted: Bool {
        microphoneGranted && inputMonitoringGranted && accessibilityGranted
    }

    var noneGranted: Bool {
        !microphoneGranted && !inputMonitoringGranted && !accessibilityGranted
    }

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    // MARK: Lifecycle

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = activationObserver {
            NotificationCenter.default.removeObserver(obs)
            activationObserver = nil
        }
    }

    func check() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let im  = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let ax  = AXIsProcessTrusted()

        var changed = false
        if microphoneGranted     != mic { microphoneGranted     = mic; changed = true }
        if inputMonitoringGranted != im { inputMonitoringGranted = im; changed = true }
        if accessibilityGranted  != ax  { accessibilityGranted  = ax;  changed = true }
        if changed { changeStamp &+= 1 }
    }

    // MARK: Requests + deep links

    /// Microphone — uses the standard macOS prompt the first time
    /// (when status is notDetermined), otherwise opens the Settings
    /// pane so the user can flip the toggle manually.
    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.check() }
            }
        } else {
            openMicrophoneSettings()
        }
    }

    /// Input Monitoring — no programmatic prompt is exposed; the macOS
    /// prompt only triggers when a CGEventTap is first created. Best
    /// fallback is to send the user straight to the Settings pane.
    func requestInputMonitoring() {
        openInputMonitoringSettings()
    }

    /// Accessibility — triggers the system prompt the first time and
    /// always opens the Settings pane after so the user has a path
    /// regardless of whether the prompt actually showed.
    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    func openMicrophoneSettings()     { openSettings(section: "Privacy_Microphone") }
    func openInputMonitoringSettings(){ openSettings(section: "Privacy_ListenEvent") }
    func openAccessibilitySettings()  { openSettings(section: "Privacy_Accessibility") }

    private func openSettings(section: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?\(section)",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Repair
//
// Bundles three steps into one user-visible action: reset Flowa's TCC
// entries, force LaunchServices to treat the installed bundle as the
// canonical one, then relaunch the app so the new process picks up the
// freshly cleared permission state.

enum Repair {

    static func run() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.maxkongerskov.Flowa"
        let bundlePath = Bundle.main.bundlePath

        // 1. Reset TCC for the three services we use. tccutil doesn't
        //    require admin to reset *our own* bundle's entries.
        runProcess("/usr/bin/tccutil", ["reset", "Microphone",    bundleId])
        runProcess("/usr/bin/tccutil", ["reset", "ListenEvent",   bundleId])
        runProcess("/usr/bin/tccutil", ["reset", "Accessibility", bundleId])

        // 2. Force-register our bundle path as the canonical Flowa, so
        //    `open Flowa` and Spotlight launches both resolve here
        //    instead of to a stale duplicate cached from an old archive.
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/"
                       + "Frameworks/LaunchServices.framework/Support/lsregister"
        runProcess(lsregister, ["-f", bundlePath])

        // 3. Relaunch — spawn a detached subshell that waits a second
        //    then re-opens us, then terminate. The `&` puts the inner
        //    pipeline into the background so it survives our exit.
        let cmd = "(sleep 1; open '\(bundlePath)') &"
        runProcess("/bin/bash", ["-c", cmd])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private static func runProcess(_ path: String, _ args: [String]) {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[Flowa][repair] \(path) failed: \(error.localizedDescription)")
        }
    }
}
