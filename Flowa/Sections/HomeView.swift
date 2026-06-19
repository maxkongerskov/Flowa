// HomeView.swift
// Flowa
//
// Settings-rows layout — feels like a native macOS preferences pane.
// Locked window dimensions in FlowaApp constrain this view to a fixed
// frame so spacing stays calibrated.
//
//   • Header: wordmark + Ready pill + sun/moon toggle
//   • Permission banners (Fn conflict, missing Accessibility)
//   • A single rounded card of four settings rows
//     (Shortcut · Language · Microphone · Model)
//   • Recent dictations as a quiet list below

import SwiftUI

struct HomeView: View {
    @ObservedObject var hotkey: GlobalHotkey
    @ObservedObject var conflict: FnConflictDetector
    @ObservedObject var permissions: PermissionChecker

    @AppStorage("flowa.colorScheme.dark") private var darkMode: Bool = false
    @AppStorage("flowa.language") private var language: String = "en"
    @AppStorage("flowa.microphone") private var microphoneUID: String = "default"
    /// Mirrors the real SMAppService state — written by the toggle,
    /// read on launch + every time Home renders so the UI stays in
    /// sync if the user changes it in System Settings → Login Items.
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    @State private var languagePickerOpen: Bool = false
    @State private var languageQuery: String = ""
    @State private var showingClearConfirm: Bool = false
    @State private var acknowledgementsOpen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
        .alert("Clear recent dictations?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) { hotkey.pipeline.clearRecent() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All \(hotkey.pipeline.recent.count) transcripts will be removed. This can't be undone.")
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

    // MARK: - Settings card

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
            settingRow(icon: "info.circle",
                       label: "Acknowledgements",
                       value: { acknowledgementsChevron })
        }
        .padding(.horizontal, 16)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .sheet(isPresented: $acknowledgementsOpen) { acknowledgementsSheet }
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

    private var acknowledgementsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Acknowledgements")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("Done") { acknowledgementsOpen = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Whisper / OpenAI")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("MIT License\n\nCopyright © 2022 OpenAI\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Text("WhisperKit / Argmax")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("MIT License\n\nCopyright © 2023 Argmax, Inc.\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
        }
        .frame(width: 480, height: 500)
        .background(Theme.pageBackground)
    }

    private var launchAtLoginToggle: some View {
        Toggle("", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.isEnabled = newValue
                // Re-read so the UI reflects the actual SMAppService
                // status (the set could fail silently if SIP / TCC say
                // no — in which case the toggle just snaps back).
                launchAtLogin = LoginItem.isEnabled
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.small)
    }

    private var microphoneMenu: some View {
        // Re-enumerate every time the menu opens so newly-plugged
        // devices appear without a relaunch.
        let devices = AudioDeviceManager.listInputs()
        let currentName: String = {
            if microphoneUID == "default" { return "System default" }
            return devices.first(where: { $0.uid == microphoneUID })?.name ?? "System default"
        }()
        return Menu {
            Button {
                microphoneUID = "default"
            } label: {
                if microphoneUID == "default" {
                    Label("System default", systemImage: "checkmark")
                } else {
                    Text("System default")
                }
            }
            if !devices.isEmpty { Divider() }
            ForEach(devices) { d in
                Button {
                    microphoneUID = d.uid
                } label: {
                    if d.uid == microphoneUID {
                        Label(d.name, systemImage: "checkmark")
                    } else {
                        Text(d.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentName)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                if !hotkey.pipeline.recent.isEmpty {
                    Button("Clear") { showingClearConfirm = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 2)

            if hotkey.pipeline.recent.isEmpty {
                emptyRecent
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hotkey.pipeline.recent.enumerated()), id: \.element.id) { i, d in
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

// MARK: - Right-side value style

private extension Text {
    func rowValueStyle() -> some View {
        self.font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
    }
}

// MARK: - Language options
//
// Full set of languages officially supported by Whisper large-v3 /
// large-v3-turbo — 99 entries plus an Auto-detect sentinel that
// maps to nil in Transcriber. Sorted alphabetically by display name
// after Auto-detect so users can find their language quickly.

struct LanguageOption {
    let code: String
    let displayName: String

    static let all: [LanguageOption] = {
        let auto = LanguageOption(code: "auto", displayName: "Auto-detect")
        let langs: [LanguageOption] = [
            LanguageOption(code: "af",  displayName: "Afrikaans"),
            LanguageOption(code: "sq",  displayName: "Albanian"),
            LanguageOption(code: "am",  displayName: "Amharic"),
            LanguageOption(code: "ar",  displayName: "Arabic"),
            LanguageOption(code: "hy",  displayName: "Armenian"),
            LanguageOption(code: "as",  displayName: "Assamese"),
            LanguageOption(code: "az",  displayName: "Azerbaijani"),
            LanguageOption(code: "ba",  displayName: "Bashkir"),
            LanguageOption(code: "eu",  displayName: "Basque"),
            LanguageOption(code: "be",  displayName: "Belarusian"),
            LanguageOption(code: "bn",  displayName: "Bengali"),
            LanguageOption(code: "bs",  displayName: "Bosnian"),
            LanguageOption(code: "br",  displayName: "Breton"),
            LanguageOption(code: "bg",  displayName: "Bulgarian"),
            LanguageOption(code: "my",  displayName: "Burmese"),
            LanguageOption(code: "yue", displayName: "Cantonese"),
            LanguageOption(code: "ca",  displayName: "Catalan"),
            LanguageOption(code: "zh",  displayName: "Chinese"),
            LanguageOption(code: "hr",  displayName: "Croatian"),
            LanguageOption(code: "cs",  displayName: "Czech"),
            LanguageOption(code: "da",  displayName: "Danish"),
            LanguageOption(code: "nl",  displayName: "Dutch"),
            LanguageOption(code: "en",  displayName: "English"),
            LanguageOption(code: "et",  displayName: "Estonian"),
            LanguageOption(code: "fo",  displayName: "Faroese"),
            LanguageOption(code: "fi",  displayName: "Finnish"),
            LanguageOption(code: "fr",  displayName: "French"),
            LanguageOption(code: "gl",  displayName: "Galician"),
            LanguageOption(code: "ka",  displayName: "Georgian"),
            LanguageOption(code: "de",  displayName: "German"),
            LanguageOption(code: "el",  displayName: "Greek"),
            LanguageOption(code: "gu",  displayName: "Gujarati"),
            LanguageOption(code: "ht",  displayName: "Haitian Creole"),
            LanguageOption(code: "ha",  displayName: "Hausa"),
            LanguageOption(code: "haw", displayName: "Hawaiian"),
            LanguageOption(code: "he",  displayName: "Hebrew"),
            LanguageOption(code: "hi",  displayName: "Hindi"),
            LanguageOption(code: "hu",  displayName: "Hungarian"),
            LanguageOption(code: "is",  displayName: "Icelandic"),
            LanguageOption(code: "id",  displayName: "Indonesian"),
            LanguageOption(code: "it",  displayName: "Italian"),
            LanguageOption(code: "ja",  displayName: "Japanese"),
            LanguageOption(code: "jw",  displayName: "Javanese"),
            LanguageOption(code: "kn",  displayName: "Kannada"),
            LanguageOption(code: "kk",  displayName: "Kazakh"),
            LanguageOption(code: "km",  displayName: "Khmer"),
            LanguageOption(code: "ko",  displayName: "Korean"),
            LanguageOption(code: "lo",  displayName: "Lao"),
            LanguageOption(code: "la",  displayName: "Latin"),
            LanguageOption(code: "lv",  displayName: "Latvian"),
            LanguageOption(code: "ln",  displayName: "Lingala"),
            LanguageOption(code: "lt",  displayName: "Lithuanian"),
            LanguageOption(code: "lb",  displayName: "Luxembourgish"),
            LanguageOption(code: "mk",  displayName: "Macedonian"),
            LanguageOption(code: "mg",  displayName: "Malagasy"),
            LanguageOption(code: "ms",  displayName: "Malay"),
            LanguageOption(code: "ml",  displayName: "Malayalam"),
            LanguageOption(code: "mt",  displayName: "Maltese"),
            LanguageOption(code: "mi",  displayName: "Maori"),
            LanguageOption(code: "mr",  displayName: "Marathi"),
            LanguageOption(code: "mn",  displayName: "Mongolian"),
            LanguageOption(code: "ne",  displayName: "Nepali"),
            LanguageOption(code: "no",  displayName: "Norwegian"),
            LanguageOption(code: "nn",  displayName: "Norwegian Nynorsk"),
            LanguageOption(code: "oc",  displayName: "Occitan"),
            LanguageOption(code: "ps",  displayName: "Pashto"),
            LanguageOption(code: "fa",  displayName: "Persian"),
            LanguageOption(code: "pl",  displayName: "Polish"),
            LanguageOption(code: "pt",  displayName: "Portuguese"),
            LanguageOption(code: "pa",  displayName: "Punjabi"),
            LanguageOption(code: "ro",  displayName: "Romanian"),
            LanguageOption(code: "ru",  displayName: "Russian"),
            LanguageOption(code: "sa",  displayName: "Sanskrit"),
            LanguageOption(code: "sr",  displayName: "Serbian"),
            LanguageOption(code: "sn",  displayName: "Shona"),
            LanguageOption(code: "sd",  displayName: "Sindhi"),
            LanguageOption(code: "si",  displayName: "Sinhala"),
            LanguageOption(code: "sk",  displayName: "Slovak"),
            LanguageOption(code: "sl",  displayName: "Slovenian"),
            LanguageOption(code: "so",  displayName: "Somali"),
            LanguageOption(code: "es",  displayName: "Spanish"),
            LanguageOption(code: "su",  displayName: "Sundanese"),
            LanguageOption(code: "sw",  displayName: "Swahili"),
            LanguageOption(code: "sv",  displayName: "Swedish"),
            LanguageOption(code: "tl",  displayName: "Tagalog"),
            LanguageOption(code: "tg",  displayName: "Tajik"),
            LanguageOption(code: "ta",  displayName: "Tamil"),
            LanguageOption(code: "tt",  displayName: "Tatar"),
            LanguageOption(code: "te",  displayName: "Telugu"),
            LanguageOption(code: "th",  displayName: "Thai"),
            LanguageOption(code: "bo",  displayName: "Tibetan"),
            LanguageOption(code: "tr",  displayName: "Turkish"),
            LanguageOption(code: "tk",  displayName: "Turkmen"),
            LanguageOption(code: "uk",  displayName: "Ukrainian"),
            LanguageOption(code: "ur",  displayName: "Urdu"),
            LanguageOption(code: "uz",  displayName: "Uzbek"),
            LanguageOption(code: "vi",  displayName: "Vietnamese"),
            LanguageOption(code: "cy",  displayName: "Welsh"),
            LanguageOption(code: "yi",  displayName: "Yiddish"),
            LanguageOption(code: "yo",  displayName: "Yoruba"),
        ]
        return [auto] + langs.sorted { $0.displayName < $1.displayName }
    }()

    static func displayName(for code: String) -> String {
        all.first(where: { $0.code == code })?.displayName ?? code
    }
}

// MARK: - Recent row
//
// One row of the Recent dictations list. Lifted out of HomeView so
// each row can hold its own short-lived "copied" state without
// polluting the parent.

private struct RecentRow: View {
    let dictation: Dictation
    let metaText: String
    @State private var copied: Bool = false
    @State private var hovering: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\u{201C}\(dictation.text)\u{201D}")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metaText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            copyButton
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var copyButton: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(dictation.text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(copied ? Theme.success : Theme.textTertiary)
                .frame(width: 24, height: 24)
                .background(hovering || copied ? Theme.surfaceMuted : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy to clipboard")
    }
}

// MARK: - Searchable language picker
//
// Popover that opens when the user clicks the Language row's value.
// Hosts a SearchField at the top + a scrolling list of matching
// languages below. Type-to-filter is the primary interaction; clicking
// a row selects + dismisses. The picker auto-focuses the search field
// on open so the user can start typing immediately.

private struct LanguagePicker: View {
    @Binding var query: String
    let selected: String
    let onSelect: (String) -> Void

    @FocusState private var searchFocused: Bool

    private var matches: [LanguageOption] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return LanguageOption.all }
        return LanguageOption.all.filter {
            $0.displayName.lowercased().contains(q)
                || $0.code.lowercased().hasPrefix(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                TextField("Search languages", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = matches.first { onSelect(first.code) }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.vertical, 18)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(matches, id: \.code) { opt in
                            row(opt)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .background(Theme.cardBackground)
        }
        .frame(width: 260)
        .onAppear { searchFocused = true }
    }

    private func row(_ opt: LanguageOption) -> some View {
        Button {
            onSelect(opt.code)
        } label: {
            HStack(spacing: 8) {
                Text(opt.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if opt.code == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(LanguageRowButtonStyle())
    }
}

private struct LanguageRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceMuted : Color.clear)
            .background(HoverHighlight())
    }
}

/// Background view that highlights on hover — gives the language rows
/// a normal menu-row feel without needing an explicit @State per row.
private struct HoverHighlight: View {
    @State private var hovering = false
    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.surfaceMuted : Color.clear)
            .onHover { hovering = $0 }
    }
}

// MARK: - Status pill

private struct StatusPill: View {
    let isReady: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isReady ? Theme.success : Theme.warning)
                .frame(width: 6, height: 6)
            Text(isReady ? "Ready" : "Setup needed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.divider, lineWidth: 0.5))
    }
}

// MARK: - Dark mode toggle

private struct DarkModeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(systemName: "sun.max.fill", active: !isOn) { isOn = false }
            segment(systemName: "moon.fill",   active:  isOn) { isOn = true  }
        }
        .padding(2)
        .background(Theme.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.divider, lineWidth: 0.5))
    }

    private func segment(systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 16)
                .foregroundColor(active ? Theme.cardBackground : Theme.textTertiary)
                .background(active ? Theme.accent : Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Conflict banner

private struct ConflictBanner: View {
    let behavior: FnConflictDetector.AppleFnBehavior
    let onFix: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.warning)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple's Fn key handler is active")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text("Set \"Press 🌐 key to\" to Do Nothing in Keyboard settings.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open", action: onFix)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.warning.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Permission banner
//
// Reusable yellow banner for any missing TCC permission. Used by
// HomeView to surface Microphone, Input Monitoring, and Accessibility
// problems when the user is past onboarding but later revoked or
// macOS has invalidated one of the grants.

struct PermissionBanner: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Theme.warning)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(Theme.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.warning.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Installing view
//
// Shown once per machine, after onboarding, while the first CoreML
// model compile runs (~2 minutes on Apple Silicon). Framed as an
// "installation" rather than a "download" because (a) nothing's
// actually downloading — the model bundle is local — and (b) users
// are used to one-time install screens. The progress bar fills over
// ~130 s and locks at 99% until Transcriber.status flips to .ready,
// at which point it jumps to 100% and dismisses.

struct InstallingView: View {
    @ObservedObject var transcriber: Transcriber
    let onComplete: () -> Void

    @State private var progress: Double = 0.0
    @State private var timer: Timer? = nil
    @State private var startTime: Date = Date()

    /// Rough estimate of the full prewarm budget on Apple Silicon.
    /// Tuned to match the observed ~112 s with a 15 % buffer so the
    /// bar usually reaches 99 % at or just after `.ready` lands.
    private let targetSeconds: Double = 130.0

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 14) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)

                HStack(alignment: .firstTextBaseline) {
                    Text(stepLabel)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(18)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 0.5)
            )
            .padding(.horizontal, 22)

            Spacer()

            footnote
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground)
        .onAppear {
            startTime = Date()
            startProgressTimer()
            checkStatus()
        }
        .onChange(of: transcriber.status) { _, _ in
            checkStatus()
        }
        .onDisappear { timer?.invalidate() }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Installing Flowa")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            Text("Optimizing the speech engine for your Mac. This only happens once.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
            Text("Runs entirely on-device. No audio leaves your Mac.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var stepLabel: String {
        if progress >= 1.0 {
            return "Ready"
        }
        let remaining = max(0, Int(targetSeconds * (1.0 - progress)))
        return "Compiling speech model · about \(remaining) seconds left"
    }

    // MARK: - Progress driver

    private func startProgressTimer() {
        let updateInterval: Double = 0.4
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            Task { @MainActor in
                advanceProgress(by: updateInterval)
                checkStatus()
            }
        }
    }

    @MainActor
    private func advanceProgress(by interval: Double) {
        // Linear ramp to 0.99 over the estimated budget. We never let
        // the bar pre-empt the actual model load — it parks at 99 %
        // until the transcriber reports .ready.
        let increment = interval / targetSeconds
        if progress < 0.99 {
            progress = min(0.99, progress + increment)
        }
    }

    @MainActor
    private func checkStatus() {
        if transcriber.status == .ready {
            progress = 1.0
            timer?.invalidate()
            timer = nil
            // Small delay so the user sees the bar hit 100 % before
            // we slide them to Home.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onComplete()
            }
        }
    }
}

// MARK: - Onboarding view
//
// Shown on first launch (and any time a fresh install hasn't been
// granted all three TCC permissions yet). Walks the user through
// Microphone → Input Monitoring → Accessibility one by one. Each row
// shows the live status; the Get Started button at the bottom only
// activates once all three are green.

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

    // MARK: - Hero

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

    // MARK: - Step row

    private func step(index: Int,
                      icon: String,
                      title: String,
                      detail: String,
                      granted: Bool,
                      actionTitle: String,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Status dot + step number
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

            // Title + detail
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
