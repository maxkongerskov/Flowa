// FnConflictDetector.swift
// Flowa
//
// Detects whether Apple's Fn key handler is hijacking the key
// (Keyboard Settings → "Press 🌐 key to").

import Foundation
import AppKit

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
        SystemSettings.openKeyboard()
    }
}
