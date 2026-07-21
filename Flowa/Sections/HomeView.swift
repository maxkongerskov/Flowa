// HomeView.swift
// Flowa
//
// Main settings + recent dictations. First-run screens live under Onboarding/.

import SwiftUI
import AppKit

struct HomeView: View {
    @ObservedObject var pipeline: DictationPipeline
    @ObservedObject var conflict: FnConflictDetector
    @ObservedObject var permissions: PermissionChecker

    @AppStorage(PrefKey.colorSchemeDark) private var darkMode: Bool = true
    @AppStorage(PrefKey.language) private var language: String = "en"
    @AppStorage(PrefKey.microphone) private var microphoneUID: String = "default"

    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var languagePickerOpen: Bool = false
    @State private var languageQuery: String = ""
    @State private var showingClearConfirm: Bool = false
    @State private var acknowledgementsOpen: Bool = false
    @State private var recentQuery: String = ""
    /// Typed max-duration field (minutes). Synced from Preferences on appear / commit.
    @State private var maxDurationField: String = "\(Preferences.maxDurationMinutes)"
    /// Cached input devices — refreshed on appear / when opening the menu, not every body pass.
    @State private var inputDevices: [AudioInputDevice] = []

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = pipeline.lastErrorMessage {
                        ErrorBanner(message: message, onDismiss: pipeline.dismissError)
                    }
                    if case .error(let modelMessage) = pipeline.transcriber.status {
                        StatusBanner(
                            severity: .danger,
                            title: "Installation needs attention",
                            detail: modelMessage,
                            actionTitle: "Install again",
                            action: { pipeline.reinstallSpeechModel() }
                        )
                    }
                    if case .conflict(let behavior) = conflict.status {
                        ConflictBanner(behavior: behavior, onFix: conflict.openKeyboardSettings)
                    }
                    if !permissions.microphoneGranted {
                        PermissionBanner(
                            title: "Microphone access needed",
                            detail: "Without it, Flowa can't capture your voice.",
                            actionTitle: "Grant",
                            action: permissions.requestMicrophone
                        )
                    }
                    if !permissions.inputMonitoringGranted {
                        PermissionBanner(
                            title: "Input Monitoring needed for the Fn key",
                            detail: "Without it, Flowa can't see when you press Fn.",
                            actionTitle: "Open",
                            action: permissions.requestInputMonitoring
                        )
                    }
                    if !permissions.accessibilityGranted {
                        PermissionBanner(
                            title: "Accessibility needed for auto-paste",
                            detail: "Without it, dictations only land on the clipboard.",
                            actionTitle: "Grant",
                            action: permissions.requestAccessibility
                        )
                    }

                    settingsCard
                    recentSection
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.pageBackground)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            maxDurationField = "\(Preferences.maxDurationMinutes)"
            refreshInputDevices()
        }
        .alert("Clear recent dictations?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) { pipeline.clearRecent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(pipeline.recent.count) transcripts will be removed. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Flowa")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            Spacer()
            StatusPill(isReady: permissions.allGranted)
            DarkModeToggle(isOn: $darkMode)
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(icon: "command",
                       label: "Shortcut",
                       value: { Text("Press fn to toggle").rowValueStyle() })
            divider
            settingRow(icon: "globe",
                       label: "Language",
                       value: { languageMenu })
            divider
            settingRow(icon: "mic",
                       label: "Microphone",
                       value: { microphoneMenu })
            divider
            settingRow(icon: "power",
                       label: "Launch at login",
                       value: { launchAtLoginToggle })
            divider
            maxDurationRow
            divider
            settingRow(icon: "info.circle",
                       label: "Acknowledgements",
                       value: { acknowledgementsChevron })
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $acknowledgementsOpen) {
            AcknowledgementsView(isPresented: $acknowledgementsOpen)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.divider, lineWidth: 0.5)
        )
    }

    private func settingRow<V: View>(icon: String,
                                     label: String,
                                     @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 16, alignment: .center)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
            Spacer(minLength: 8)
            value()
        }
        .frame(height: 40)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 0.5)
    }

    private var acknowledgementsChevron: some View {
        Button {
            acknowledgementsOpen = true
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
        }
        .buttonStyle(.plain)
    }

    private var launchAtLoginToggle: some View {
        Toggle("", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.isEnabled = newValue
                launchAtLogin = LoginItem.isEnabled
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.small)
    }

    /// Max recording duration — hard stop for stability; default/recommended 60 min.
    private var maxDurationRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text("Max duration")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Text("Recommended \(Preferences.recommendedMaxDurationMinutes) min · 0 = no limit")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                TextField("60", text: $maxDurationField)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .onSubmit { commitMaxDurationField() }
                Text("min")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .onChange(of: maxDurationField) { _, newValue in
            // Keep only digits while typing.
            let filtered = newValue.filter(\.isNumber)
            if filtered != newValue { maxDurationField = filtered }
        }
        .onDisappear { commitMaxDurationField() }
    }

    private func commitMaxDurationField() {
        let minutes = Preferences.maxDurationMinutes(fromField: maxDurationField)
        Preferences.maxDurationMinutes = minutes
        maxDurationField = "\(minutes)"
    }

    private func refreshInputDevices() {
        inputDevices = AudioDeviceManager.listInputsForPicker()
        // Migrate stale / ephemeral prefs to system default.
        if !Preferences.isSystemDefaultMicrophone(microphoneUID),
           !inputDevices.contains(where: { $0.uid == microphoneUID }) {
            microphoneUID = "default"
        }
    }

    private var microphoneMenu: some View {
        let currentName: String = {
            if Preferences.isSystemDefaultMicrophone(microphoneUID) { return "System default" }
            if let d = inputDevices.first(where: { $0.uid == microphoneUID }) {
                return d.displayName
            }
            return "System default"
        }()
        return Menu {
            Button {
                microphoneUID = "default"
            } label: {
                if Preferences.isSystemDefaultMicrophone(microphoneUID) {
                    Label("System default", systemImage: "checkmark")
                } else {
                    Text("System default")
                }
            }
            if !inputDevices.isEmpty { Divider() }
            ForEach(inputDevices) { d in
                Button {
                    microphoneUID = d.uid
                } label: {
                    if d.uid == microphoneUID {
                        Label(d.displayName, systemImage: "checkmark")
                    } else {
                        Text(d.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentName)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onTapGesture { refreshInputDevices() }
    }

    private var languageMenu: some View {
        Button {
            languageQuery = ""
            languagePickerOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(LanguageOption.displayName(for: language))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $languagePickerOpen, arrowEdge: .top) {
            LanguagePicker(
                query: $languageQuery,
                selected: language,
                onSelect: { code in
                    language = code
                    languagePickerOpen = false
                }
            )
        }
    }

    // MARK: - Recent

    private var filteredRecent: [Dictation] {
        let q = recentQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pipeline.recent }
        return pipeline.recent.filter { $0.text.lowercased().contains(q) }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("RECENT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                if !pipeline.recent.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                        TextField("", text: $recentQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: 80)
                        if !recentQuery.isEmpty {
                            Button { recentQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Button("Clear") { showingClearConfirm = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 2)

            if pipeline.recent.isEmpty {
                emptyRecent
            } else if filteredRecent.isEmpty {
                Text("No results for \"\(recentQuery)\"")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.divider, lineWidth: 0.5)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRecent.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { divider }
                        RecentRow(dictation: d, metaText: meta(for: d))
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 0.5)
                )
            }
        }
    }

    private var emptyRecent: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(Theme.textTertiary)
            Text("No dictations yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text("Press fn anywhere and speak.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.divider, lineWidth: 0.5)
        )
    }

    private func meta(for d: Dictation) -> String {
        let age = Self.relative.localizedString(for: d.date, relativeTo: Date())
        if let app = d.targetAppName, !app.isEmpty {
            return "\(age) · \(app)"
        }
        return age
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
