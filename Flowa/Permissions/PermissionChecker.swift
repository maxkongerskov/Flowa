// PermissionChecker.swift
// Flowa
//
// Live status of the three TCC permissions Flowa needs.
// Polls on a timer + on app activation so grants in System Settings
// appear as soon as the user returns.

import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import IOKit
import IOKit.hid

@MainActor
final class PermissionChecker: ObservableObject {

    @Published private(set) var microphoneGranted: Bool = false
    @Published private(set) var inputMonitoringGranted: Bool = false
    @Published private(set) var accessibilityGranted: Bool = false

    var allGranted: Bool {
        microphoneGranted && inputMonitoringGranted && accessibilityGranted
    }

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

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

        if microphoneGranted      != mic { microphoneGranted      = mic }
        if inputMonitoringGranted != im  { inputMonitoringGranted = im  }
        if accessibilityGranted   != ax  { accessibilityGranted   = ax  }
    }

    /// Microphone — system prompt when notDetermined; otherwise Settings.
    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.check() }
            }
        } else {
            SystemSettings.openMicrophone()
        }
    }

    /// Input Monitoring — no programmatic prompt; open Settings.
    func requestInputMonitoring() {
        SystemSettings.openInputMonitoring()
    }

    /// Accessibility — prompt once, then open Settings as a reliable path.
    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        SystemSettings.openAccessibility()
    }
}
