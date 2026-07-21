// SystemSettings.swift
// Flowa
//
// Canonical deep links into System Settings privacy panes.

import AppKit
import Foundation

enum SystemSettings {

    static func openMicrophone() {
        openPrivacy(section: "Privacy_Microphone")
    }

    static func openInputMonitoring() {
        openPrivacy(section: "Privacy_ListenEvent")
    }

    static func openAccessibility() {
        openPrivacy(section: "Privacy_Accessibility")
    }

    static func openKeyboard() {
        for s in [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ] {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    private static func openPrivacy(section: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?\(section)",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }
}
