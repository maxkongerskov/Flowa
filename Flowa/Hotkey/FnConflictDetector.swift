// FnConflictDetector.swift
// Flowa
//
// Permission / conflict detectors. Two ObservableObjects co-located
// here because they both answer the same shape of question: "is the
// system in a state that silently breaks Flowa?". Split into separate
// files when the project file is regenerated.
//
// FnConflictDetector — Apple's Fn handler hijacking the key.
// AccessibilityChecker — Cmd+V synthesis silently dropped without
// Accessibility permission.

import Foundation
import AppKit
import ApplicationServices

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

// MARK: - AccessibilityChecker
//
// Without Accessibility permission, CGEvent.post(tap: .cghidEventTap)
// is silently dropped — the clipboard write succeeds but the
// synthetic Cmd+V never reaches the focused app. We detect this on
// launch and surface a banner on Home so the user can grant it.

@MainActor
final class AccessibilityChecker: ObservableObject {

    @Published private(set) var isTrusted: Bool = false

    private var timer: Timer?

    func start() {
        check()
        // Re-check every 2 s so that when the user grants the permission
        // in Settings, the banner clears without needing a relaunch (in
        // newer macOS the permission updates live for the running app).
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Prompt + open Accessibility settings. On first call macOS shows
    /// its "Flowa would like to control your computer" sheet with a
    /// direct path to Settings; on subsequent calls we open Settings
    /// ourselves so the user always lands in the right place.
    func requestAccess() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
