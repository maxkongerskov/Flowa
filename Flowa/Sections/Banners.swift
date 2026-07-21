// Banners.swift
// Flowa
//
// Shared status banners for home (errors, permissions, Fn conflict).

import SwiftUI

enum BannerSeverity {
    case warning
    case danger

    var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .danger:  return "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .warning: return Theme.warning
        case .danger:  return Theme.danger
        }
    }
}

struct StatusBanner: View {
    let severity: BannerSeverity
    let title: String?
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: severity.icon)
                .foregroundColor(severity.tint)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                }
                Text(detail)
                    .font(.system(size: title == nil ? 12 : 11))
                    .foregroundColor(title == nil ? Theme.textPrimary : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(10)
        .background(severity.tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(severity.tint.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        StatusBanner(
            severity: .danger,
            title: nil,
            detail: message,
            onDismiss: onDismiss
        )
    }
}

struct PermissionBanner: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        StatusBanner(
            severity: .warning,
            title: title,
            detail: detail,
            actionTitle: actionTitle,
            action: action
        )
    }
}

struct ConflictBanner: View {
    let behavior: FnConflictDetector.AppleFnBehavior
    let onFix: () -> Void

    var body: some View {
        StatusBanner(
            severity: .warning,
            title: "Apple's Fn key handler is active",
            detail: "Currently set to \"\(behavior.displayName)\". Set \"Press 🌐 key to\" to Do Nothing in Keyboard settings.",
            actionTitle: "Open",
            action: onFix
        )
    }
}
