// RootView.swift
// Flowa
//
// Routes between three top-level views based on first-run state +
// permission status + speech-model readiness:
//
//   ① OnboardingView — until all three TCC permissions are granted
//   ② InstallingView — once per machine, while Whisper does its
//                       one-time CoreML compile (~2 min on Apple
//                       Silicon). Skipped if the model is already
//                       compiled from a previous launch.
//   ③ HomeView       — main app. Banners surface any permission
//                       that gets revoked after install.

import SwiftUI

struct RootView: View {
    @ObservedObject var hotkey: GlobalHotkey
    @ObservedObject var conflict: FnConflictDetector
    @ObservedObject var permissions: PermissionChecker

    @AppStorage("flowa.onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("flowa.firstRunComplete")  private var firstRunComplete:  Bool = false

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView(permissions: permissions) {
                    onboardingComplete = true
                }
                .transition(.opacity)
            } else if shouldShowInstalling {
                InstallingView(transcriber: hotkey.pipeline.transcriber) {
                    firstRunComplete = true
                }
                .transition(.opacity)
            } else {
                HomeView(
                    hotkey: hotkey,
                    conflict: conflict,
                    permissions: permissions
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowOnboarding)
        .animation(.easeInOut(duration: 0.2), value: shouldShowInstalling)
        .onAppear {
            // Upgrade case: if all permissions already granted on first
            // render, mark onboarding done so we don't re-prompt.
            if permissions.allGranted { onboardingComplete = true }
            // And if the model is already loaded (rare — would mean
            // prewarm raced to completion before this view rendered),
            // skip the install screen too.
            if hotkey.pipeline.transcriber.status == .ready {
                firstRunComplete = true
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        !onboardingComplete && !permissions.allGranted
    }

    private var shouldShowInstalling: Bool {
        !firstRunComplete && hotkey.pipeline.transcriber.status != .ready
    }
}
