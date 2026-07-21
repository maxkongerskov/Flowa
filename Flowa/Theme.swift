// Theme.swift
// Flowa
//
// Centralised colour and type tokens. Every colour is *dynamic* —
// it resolves to a different value depending on whether the system
// (or our PrefKey.colorSchemeDark / preferredColorScheme) is currently
// light or dark. SwiftUI views that read these tokens auto-update
// when the user flips the sun/moon toggle on the Home page.

import SwiftUI
import AppKit

enum Theme {

    // MARK: - Surfaces

    /// The window background. Slightly off-white in light, deep near-
    /// black in dark.
    static let pageBackground = dynamic(
        light: Color(red: 0.957, green: 0.957, blue: 0.957),
        dark:  Color(red: 0.102, green: 0.102, blue: 0.110)
    )

    /// Card surface — sits on top of pageBackground.
    static let cardBackground = dynamic(
        light: Color.white,
        dark:  Color(red: 0.149, green: 0.149, blue: 0.157)
    )

    /// Inset surface — used for muted pills, sub-cards.
    static let surfaceMuted = dynamic(
        light: Color(red: 0.945, green: 0.945, blue: 0.943),
        dark:  Color(red: 0.196, green: 0.196, blue: 0.204)
    )

    /// Strong accent — primary CTA, active states. Flips to white-ish
    /// in dark so it stays high-contrast against the deep background.
    static let accent = dynamic(
        light: Color(red: 0.118, green: 0.118, blue: 0.122),
        dark:  Color(red: 0.949, green: 0.949, blue: 0.953)
    )

    /// 0.5pt divider stroke.
    static let divider = dynamic(
        light: Color.black.opacity(0.08),
        dark:  Color.white.opacity(0.08)
    )

    // MARK: - Text

    static let textPrimary = dynamic(
        light: Color(red: 0.102, green: 0.102, blue: 0.106),
        dark:  Color(red: 0.949, green: 0.949, blue: 0.953)
    )

    static let textSecondary = dynamic(
        light: Color(red: 0.376, green: 0.376, blue: 0.380),
        dark:  Color(red: 0.643, green: 0.643, blue: 0.659)
    )

    static let textTertiary = dynamic(
        light: Color(red: 0.612, green: 0.612, blue: 0.616),
        dark:  Color(red: 0.478, green: 0.478, blue: 0.494)
    )

    // MARK: - Semantic

    static let success = dynamic(
        light: Color(red: 0.227, green: 0.624, blue: 0.404),
        dark:  Color(red: 0.345, green: 0.741, blue: 0.522)
    )

    static let warning = dynamic(
        light: Color(red: 0.929, green: 0.604, blue: 0.227),
        dark:  Color(red: 0.984, green: 0.690, blue: 0.337)
    )

    static let danger = dynamic(
        light: Color(red: 0.851, green: 0.310, blue: 0.310),
        dark:  Color(red: 0.984, green: 0.408, blue: 0.408)
    )

    // MARK: - Flow Bar (the floating pill)

    /// The floating pill stays high-contrast regardless of theme — it
    /// has to read on top of any app's window, not against our page bg.
    static let flowBarBackground = Color.black.opacity(0.88)
    static let flowBarText       = Color.white

    // MARK: - Internal

    /// SwiftUI Color that auto-resolves based on NSAppearance — which
    /// SwiftUI propagates down the view tree when you set
    /// `.preferredColorScheme(.light/.dark)` at the app root.
    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }))
    }
}
