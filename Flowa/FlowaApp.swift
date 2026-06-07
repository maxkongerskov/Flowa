// FlowaApp.swift
// Flowa — voice dictation for macOS

import SwiftUI
import AppKit
import ServiceManagement

// MARK: - App delegate
//
// Keeps Flowa running when the main window is closed so the Fn
// hotkey + menu bar icon stay alive. Without this, macOS quits the
// app the moment the user clicks the red traffic-light button.

final class FlowaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Launch at login
//
// Wraps SMAppService (macOS 13+) so the rest of the app can flip the
// login-item state with a single property. SMAppService persists the
// registration in the user's login items; no special entitlement
// needed for "launch this same app at login".

enum LoginItem {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("[Flowa] Launch-at-login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}

@main
struct FlowaApp: App {
    @NSApplicationDelegateAdaptor(FlowaAppDelegate.self) private var delegate

    @StateObject private var hotkey = GlobalHotkey()
    @StateObject private var conflict = FnConflictDetector()
    @StateObject private var accessibility = AccessibilityChecker()

    /// Persisted dark-mode preference, controlled by the sun/moon
    /// toggle on the Home page. Drives .preferredColorScheme app-wide
    /// so every dynamic Theme colour resolves consistently.
    @AppStorage("flowa.colorScheme.dark") private var darkMode: Bool = false

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(
                hotkey: hotkey,
                conflict: conflict,
                accessibility: accessibility
            )
            .frame(width: 540, height: 640)
            .background(Theme.pageBackground)
            .preferredColorScheme(darkMode ? .dark : .light)
            .onAppear {
                hotkey.start()
                conflict.start()
                accessibility.start()
                print("[Flowa] launched. AXIsProcessTrusted=\(accessibility.isTrusted), loginItem=\(LoginItem.isEnabled)")
                hotkey.pipeline.prewarm()
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 640)

        // Menu bar icon — stays alive even when the main window is
        // closed. The icon tints based on permission status so the user
        // can tell at a glance whether dictation will work.
        MenuBarExtra {
            MenuBarMenu(
                isAccessibilityGranted: accessibility.isTrusted,
                isFnConflict: conflict.status != .clean
            )
        } label: {
            Image(systemName: menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    /// Pick the SF Symbol drawn in the menu bar based on current
    /// permission state. The symbol with a slash communicates
    /// "something's wrong — open Flowa".
    private var menuBarSymbolName: String {
        if !accessibility.isTrusted || conflict.status != .clean {
            return "waveform.slash"
        }
        return "waveform"
    }
}

// MARK: - Menu bar menu content
//
// The MenuBarExtra accepts a regular SwiftUI body — Buttons render as
// menu items, Divider() as separator lines. Use the SwiftUI
// environment's openWindow action to bring the main window back when
// it has been closed.

private struct MenuBarMenu: View {
    let isAccessibilityGranted: Bool
    let isFnConflict: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Flowa") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: [.command])

        Divider()

        if !isAccessibilityGranted {
            Text("Accessibility permission missing")
        } else if isFnConflict {
            Text("Apple Fn handler is hijacking the key")
        } else {
            Text("Ready — press fn to dictate")
        }

        Divider()

        Button("Quit Flowa") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
