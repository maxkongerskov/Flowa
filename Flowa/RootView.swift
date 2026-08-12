// RootView.swift
// Flowa
//
// Routes between three top-level views based on first-run state +
// permission status + speech-model readiness:
//
//   ① OnboardingView — until all three TCC permissions are granted
//   ② InstallingView — one-time CoreML prepare of the bundled engine
//                       (~10 min offline), or retry after a load error.
//   ③ HomeView       — main app. Banners surface any permission
//                       that gets revoked after install.

import SwiftUI

struct RootView: View {
    @ObservedObject var pipeline: DictationPipeline
    @ObservedObject var conflict: FnConflictDetector
    @ObservedObject var permissions: PermissionChecker

    @AppStorage(PrefKey.onboardingComplete) private var onboardingComplete: Bool = false
    @AppStorage(PrefKey.firstRunComplete)  private var firstRunComplete:  Bool = false

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView(permissions: permissions) {
                    onboardingComplete = true
                }
                .transition(.opacity)
            } else if shouldShowInstalling {
                InstallingView(transcriber: pipeline.transcriber) {
                    firstRunComplete = true
                    Preferences.markSpeechModelInstalled()
                }
                .transition(.opacity)
            } else {
                HomeView(
                    pipeline: pipeline,
                    conflict: conflict,
                    permissions: permissions
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowOnboarding)
        .animation(.easeInOut(duration: 0.2), value: shouldShowInstalling)
        .onAppear {
            if permissions.allGranted { onboardingComplete = true }
            syncFirstRunWithTranscriber()
        }
        .onChange(of: pipeline.transcriber.status) { _, _ in
            syncFirstRunWithTranscriber()
        }
    }

    private var shouldShowOnboarding: Bool {
        !onboardingComplete && !permissions.allGranted
    }

    /// Install / prepare / error — not only the first-ever launch.
    private var shouldShowInstalling: Bool {
        pipeline.transcriber.needsSetup
    }

    private func syncFirstRunWithTranscriber() {
        if pipeline.transcriber.isReady {
            firstRunComplete = true
            Preferences.markSpeechModelInstalled()
        } else if case .error = pipeline.transcriber.status {
            firstRunComplete = false
            Preferences.markSpeechModelNotInstalled()
        }
    }
}
