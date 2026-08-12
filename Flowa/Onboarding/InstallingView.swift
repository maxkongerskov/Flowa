// InstallingView.swift
// Flowa
//
// One-time install screen: may download the speech engine once (git builds),
// then stages + CoreML-specializes it for this Mac.

import SwiftUI

struct InstallingView: View {
    @ObservedObject var transcriber: Transcriber
    let onComplete: () -> Void

    @State private var tipIndex: Int = 0
    private let tipTimer = Timer.publish(every: 5.5, on: .main, in: .common).autoconnect()

    private static let tips: [String] = [
        "Press fn to start listening, speak, then press fn again — your words land where the cursor is.",
        "After setup, everything runs on this Mac. Your audio never leaves the machine.",
        "Works in Notes, Mail, chat apps, browsers, and code editors.",
        "In Keyboard settings, set “Press 🌐 key to” to Do Nothing so fn stays free for Flowa.",
        "You can switch languages anytime from Home — Flowa keeps up mid-sentence.",
        "Recent dictations stay on this Mac so you can copy them later."
    ]

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)

            card
                .padding(.horizontal, 22)

            tipCard
                .padding(.horizontal, 22)
                .padding(.top, 14)

            Spacer()

            footnote
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .onAppear { handle(status: transcriber.status, firstAppear: true) }
        .onChange(of: transcriber.status) { _, newStatus in
            handle(status: newStatus, firstAppear: false)
        }
        .onReceive(tipTimer) { _ in
            guard case .error = transcriber.status else {
                tipIndex = (tipIndex + 1) % Self.tips.count
                return
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch transcriber.status {
        case .error(let message):
            errorCard(message)
        case .downloading(let progress):
            downloadingCard(progress: progress)
        case .preparing(let progress):
            installingCard(progress: progress)
        case .idle:
            installingCard(progress: 0)
        default:
            installingCard(progress: 0.99)
        }
    }

    private func downloadingCard(progress: Double) -> some View {
        let clamped = min(1, max(0, progress))
        let percent = Int((clamped * 100).rounded())

        return VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: clamped)
                .progressViewStyle(.linear)
                .tint(Theme.accent)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading speech engine (~1.5 GB)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Text("One-time download. After this, Flowa works offline.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundColor(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.2), value: percent)
            }
        }
        .modifier(InstallCard())
    }

    private func installingCard(progress: Double) -> some View {
        let clamped = min(1, max(0, progress))
        let remaining = Int(ceil(Transcriber.expectedPrepareSeconds * (1.0 - clamped)))
        // After the ~10 min countdown, keep working — some Macs take longer.
        let pastCountdown = remaining <= 0 || clamped >= 0.99

        return VStack(alignment: .leading, spacing: 14) {
            if pastCountdown {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            } else {
                ProgressView(value: clamped)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pastCountdown
                         ? "Still installing…"
                         : "Approximately 10 minutes to install")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    if pastCountdown {
                        Text("Almost there — keep Flowa open until setup finishes.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if pastCountdown {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 18, weight: .semibold).monospacedDigit())
                        .foregroundColor(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.2), value: remaining)
                }
            }
        }
        .modifier(InstallCard())
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While you wait")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Text(Self.tips[tipIndex % Self.tips.count])
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.25), value: tipIndex)
                .id(tipIndex)
        }
        .modifier(InstallCard())
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.warning)
                Text("Installation couldn't finish")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Text("Try again")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.cardBackground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .modifier(InstallCard())
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(titleText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            Text(subtitleText)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: String {
        switch transcriber.status {
        case .error:
            return "Finish setup"
        case .downloading:
            return "Downloading Flowa"
        default:
            return "Installing Flowa"
        }
    }

    private var subtitleText: String {
        switch transcriber.status {
        case .downloading:
            return "Flowa needs the speech engine once (~1.5 GB). It is not in the git repo so clones stay small."
        default:
            return "Flowa is setting up speech recognition for this Mac. This only happens once."
        }
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            Image(systemName: isDownloading ? "wifi" : "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
            Text(isDownloading
                 ? "Internet needed for this step only. Audio never leaves your Mac."
                 : "After setup, works offline. No audio leaves your Mac.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var isDownloading: Bool {
        if case .downloading = transcriber.status { return true }
        return false
    }

    private func handle(status: Transcriber.Status, firstAppear: Bool) {
        switch status {
        case .ready:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onComplete() }
        case .idle:
            if firstAppear { retry() }
        default:
            break
        }
    }

    private func retry() {
        Task { await transcriber.loadIfNeeded() }
    }
}

private struct InstallCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 0.5)
            )
    }
}
