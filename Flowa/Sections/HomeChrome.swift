// HomeChrome.swift
// Flowa
//
// Secondary home UI pieces (recent rows, language picker, header chrome).

import SwiftUI
import AppKit

extension Text {
    func rowValueStyle() -> some View {
        self.font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
    }
}

struct RecentRow: View {
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

struct LanguagePicker: View {
    @Binding var query: String
    let selected: String
    let onSelect: (String) -> Void

    @FocusState private var searchFocused: Bool

    private var matches: [LanguageOption] {
        LanguageOption.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
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

struct LanguageRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceMuted : Color.clear)
            .background(HoverHighlight())
    }
}

struct HoverHighlight: View {
    @State private var hovering = false
    var body: some View {
        Rectangle()
            .fill(hovering ? Theme.surfaceMuted : Color.clear)
            .onHover { hovering = $0 }
    }
}

struct StatusPill: View {
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

struct DarkModeToggle: View {
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
