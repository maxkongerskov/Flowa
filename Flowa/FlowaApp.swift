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
    @StateObject private var permissions = PermissionChecker()

    @AppStorage("flowa.colorScheme.dark") private var darkMode: Bool = false

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(
                hotkey: hotkey,
                conflict: conflict,
                permissions: permissions
            )
            .frame(width: 540, height: 640)
            .background(Theme.pageBackground)
            .preferredColorScheme(darkMode ? .dark : .light)
            .onAppear {
                hotkey.start()
                conflict.start()
                permissions.start()
                print("[Flowa] launched. mic=\(permissions.microphoneGranted) im=\(permissions.inputMonitoringGranted) ax=\(permissions.accessibilityGranted) loginItem=\(LoginItem.isEnabled)")
                hotkey.pipeline.prewarm()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                permissions.check()
                // Rebuild the CGEventTap if Input Monitoring was just
                // granted in System Settings — without this, the tap
                // stays dead until full app relaunch.
                if !hotkey.isAuthorized {
                    hotkey.restart()
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 640)

        MenuBarExtra {
            MenuBarMenu(permissions: permissions, conflict: conflict)
        } label: {
            Image(systemName: menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbolName: String {
        if !permissions.allGranted || conflict.status != .clean {
            return "waveform.slash"
        }
        return "waveform"
    }
}

// MARK: - Menu bar menu

private struct MenuBarMenu: View {
    @ObservedObject var permissions: PermissionChecker
    @ObservedObject var conflict: FnConflictDetector

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Flowa") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: [.command])

        Divider()

        Text(statusText)

        Divider()

        Button("Repair Flowa…") {
            confirmAndRepair()
        }

        Divider()

        Button("Quit Flowa") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var statusText: String {
        if !permissions.microphoneGranted { return "Microphone permission missing" }
        if !permissions.inputMonitoringGranted { return "Input Monitoring permission missing" }
        if !permissions.accessibilityGranted { return "Accessibility permission missing" }
        if conflict.status != .clean { return "Apple Fn handler is active" }
        return "Ready — press fn to dictate"
    }

    /// Show an NSAlert to confirm, then run the Repair flow if the
    /// user agrees. Reuses NSAlert because SwiftUI alerts attached to
    /// a MenuBarExtra menu don't reliably display on macOS.
    private func confirmAndRepair() {
        let alert = NSAlert()
        alert.messageText = "Repair Flowa?"
        alert.informativeText = """
        This will:
        \u{2022} Reset all of Flowa's macOS permissions (Microphone, Input Monitoring, Accessibility)
        \u{2022} Re-register Flowa.app as the canonical installation
        \u{2022} Quit and relaunch the app

        You'll be prompted to grant each permission again. Use this if something stopped working after an update or reinstall.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Repair and Relaunch")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Repair.run()
        }
    }
}
