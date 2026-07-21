// MicDeviceKind.swift
// Flowa
//
// Classifies audio inputs so Continuity / iPhone mics can be labeled
// and messaged correctly without name-only hacks.

import Foundation

/// Continuity Camera wireless device transport fourcc: 'ccwd'.
enum MicTransport {
    static let continuityWireless: UInt32 = 0x6363_7764 // 'ccwd'
}

enum MicDeviceKind: Equatable {
    case standard
    case continuity

    /// Pure classifier — unit-tested. Prefer modelUID / transport over display name.
    static func classify(name: String, modelUID: String, transport: UInt32, uid: String) -> MicDeviceKind {
        let model = modelUID.lowercased()
        let n = name.lowercased()
        let u = uid.lowercased()

        if transport == MicTransport.continuityWireless { return .continuity }
        if model == "iphone mic" || model.contains("iphone mic") { return .continuity }
        if model.contains("continuity") { return .continuity }
        // Fallback for older macOS naming when modelUID is empty
        if n.contains("iphone") && (n.contains("microphone") || n.contains("mic")) {
            return .continuity
        }
        if u.contains("iphone") && u.contains("mic") { return .continuity }
        return .standard
    }

    /// User-facing label for the microphone picker / current-value row.
    static func displayName(name: String, kind: MicDeviceKind) -> String {
        switch kind {
        case .continuity:
            // Keep the system name ("Max's iPhone Microphone") and add guidance.
            if name.localizedCaseInsensitiveContains("speak") {
                return name
            }
            return "\(name) · speak near phone"
        case .standard:
            return name
        }
    }

    /// True for ephemeral Core Audio aggregates that should not be persisted
    /// as a long-lived preference (UID numbers change across reboots).
    static func isEphemeralAggregateUID(_ uid: String) -> Bool {
        uid.hasPrefix("CADefaultDeviceAggregate")
    }
}
