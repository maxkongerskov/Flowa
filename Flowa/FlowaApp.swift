// FlowaApp.swift
// Flowa — voice dictation for macOS

import SwiftUI
import AppKit
import ServiceManagement

// MARK: - App delegate
//
// Keeps Flowa running when the main window is closed so the Fn
// hotkey + menu bar icon stay alive.

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

/// Holds GlobalHotkey so the app can inject a shared DictationPipeline once.
@MainActor
final class HotkeyHolder: ObservableObject {
    let hotkey: GlobalHotkey

    init(pipeline: DictationPipeline) {
        self.hotkey = GlobalHotkey(pipeline: pipeline)
    }
}

@main
struct FlowaApp: App {
    @NSApplicationDelegateAdaptor(FlowaAppDelegate.self) private var delegate

    /// Domain orchestration owned at the app root — not by the hotkey.
    @StateObject private var pipeline: DictationPipeline
    @StateObject private var hotkeyHolder: HotkeyHolder
    @StateObject private var conflict: FnConflictDetector
    @StateObject private var permissions: PermissionChecker

    @AppStorage(PrefKey.colorSchemeDark) private var darkMode: Bool = true

    init() {
        let sharedPipeline = DictationPipeline()
        _pipeline = StateObject(wrappedValue: sharedPipeline)
        _hotkeyHolder = StateObject(wrappedValue: HotkeyHolder(pipeline: sharedPipeline))
        _conflict = StateObject(wrappedValue: FnConflictDetector())
        _permissions = StateObject(wrappedValue: PermissionChecker())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(
                pipeline: pipeline,
                conflict: conflict,
                permissions: permissions
            )
            .frame(width: 540, height: 640)
            .background(Theme.pageBackground)
            .preferredColorScheme(darkMode ? .dark : .light)
            .onAppear {
                hotkeyHolder.hotkey.start()
                conflict.start()
                permissions.start()
                print("[Flowa] launched. mic=\(permissions.microphoneGranted) im=\(permissions.inputMonitoringGranted) ax=\(permissions.accessibilityGranted) loginItem=\(LoginItem.isEnabled)")
                pipeline.prewarm()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                permissions.check()
                if !hotkeyHolder.hotkey.isAuthorized {
                    hotkeyHolder.hotkey.restart()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .flowaShowMainWindow)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                // Bring any existing Flowa window forward.
                if let window = NSApp.windows.first(where: { $0.isVisible || $0.isMiniaturized }) {
                    window.deminiaturize(nil)
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 640)

        MenuBarExtra {
            MenuBarMenu(
                pipeline: pipeline,
                permissions: permissions,
                conflict: conflict
            )
        } label: {
            Image(systemName: menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbolName: String {
        if pipeline.isTranscribing {
            return "ellipsis.circle"
        }
        if pipeline.transcriber.needsSetup {
            return "arrow.down.circle"
        }
        if !permissions.allGranted || conflict.status != .clean {
            return "waveform.slash"
        }
        return "waveform"
    }
}

// MARK: - Menu bar menu

private struct MenuBarMenu: View {
    @ObservedObject var pipeline: DictationPipeline
    @ObservedObject var permissions: PermissionChecker
    @ObservedObject var conflict: FnConflictDetector

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Flowa") {
            showMain()
        }
        .keyboardShortcut("0", modifiers: [.command])

        Divider()

        Text(statusText)

        Divider()

        Button("Re-run Installation…") {
            confirmAndReinstallModel()
        }

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
        if case .error = pipeline.transcriber.status {
            return "Installation needs attention"
        }
        if case .preparing(let p) = pipeline.transcriber.status {
            let remaining = Int(ceil(Transcriber.expectedPrepareSeconds * (1.0 - min(1, max(0, p)))))
            if remaining <= 0 { return "Installing… almost done" }
            let m = remaining / 60
            let s = remaining % 60
            return String(format: "Installing… %d:%02d", m, s)
        }
        if pipeline.transcriber.needsSetup {
            return "Installing… ~2 min"
        }
        if !permissions.microphoneGranted { return "Microphone permission missing" }
        if !permissions.inputMonitoringGranted { return "Input Monitoring permission missing" }
        if !permissions.accessibilityGranted { return "Accessibility permission missing" }
        if conflict.status != .clean { return "Apple Fn handler is active" }
        if pipeline.isTranscribing { return "Transcribing…" }
        return "Ready — press fn to dictate"
    }

    private func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        NotificationCenter.default.post(name: .flowaShowMainWindow, object: nil)
    }

    private func confirmAndReinstallModel() {
        let alert = NSAlert()
        alert.messageText = "Re-run installation?"
        alert.informativeText = """
        This prepares Flowa’s speech engine again for this Mac (about two minutes). Nothing is downloaded — the engine is already inside the app.

        Use this if dictation records but never produces text.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install again")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            pipeline.reinstallSpeechModel()
            showMain()
        }
    }

    private func confirmAndRepair() {
        let alert = NSAlert()
        alert.messageText = "Repair Flowa?"
        alert.informativeText = """
        This will:
        \u{2022} Reset Microphone, Input Monitoring, and Accessibility permissions
        \u{2022} Re-run the one-time speech engine install for this Mac
        \u{2022} Re-register Flowa.app and relaunch

        You'll grant permissions again; installation is offline. Use this after moving Flowa or if something stopped working.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Repair and Relaunch")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Repair.run(options: .all)
        }
    }
}
