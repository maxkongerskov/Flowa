// OnboardingView.swift
// Flowa
//
// First-run walkthrough for Microphone, Input Monitoring, and Accessibility.

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionChecker
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 22)

            VStack(spacing: 10) {
                step(
                    index: 1,
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Captures your voice so Whisper can transcribe it locally on your Mac.",
                    granted: permissions.microphoneGranted,
                    actionTitle: "Allow microphone",
                    action: permissions.requestMicrophone
                )
                step(
                    index: 2,
                    icon: "command",
                    title: "Input Monitoring",
                    detail: "Lets Flowa see when you press the Fn key. Doesn't read what you type.",
                    granted: permissions.inputMonitoringGranted,
                    actionTitle: "Open Settings",
                    action: permissions.requestInputMonitoring
                )
                step(
                    index: 3,
                    icon: "lock.shield.fill",
                    title: "Accessibility",
                    detail: "Lets Flowa paste your transcripts into the focused app. Cmd+V only — nothing else.",
                    granted: permissions.accessibilityGranted,
                    actionTitle: "Allow accessibility",
                    action: permissions.requestAccessibility
                )
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 12)

            Button(action: onComplete) {
                Text(permissions.allGranted ? "Get started" : "Waiting for all three…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(permissions.allGranted ? Theme.cardBackground : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(permissions.allGranted ? Theme.accent : Theme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!permissions.allGranted)
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Welcome to Flowa")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            Text("Voice dictation that runs entirely on your Mac. Three quick permissions and you're set.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(index: Int,
                      icon: String,
                      title: String,
                      detail: String,
                      granted: Bool,
                      actionTitle: String,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? Theme.success : Theme.surfaceMuted)
                    .frame(width: 26, height: 26)
                if granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.cardBackground)
                } else {
                    Text("\(index)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(granted ? Theme.success.opacity(0.4) : Theme.divider, lineWidth: 0.5)
        )
    }
}
