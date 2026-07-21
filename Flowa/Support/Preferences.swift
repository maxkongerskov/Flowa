// Preferences.swift
// Flowa
//
// Single source of truth for UserDefaults keys and typed accessors.
// Capture / transcription receive values from callers; they do not
// read raw "flowa.…" strings themselves.

import Foundation

enum PrefKey {
    static let language = "flowa.language"
    static let microphone = "flowa.microphone"
    static let colorSchemeDark = "flowa.colorScheme.dark"
    static let onboardingComplete = "flowa.onboardingComplete"
    static let firstRunComplete = "flowa.firstRunComplete"
    /// Integer minutes. Default / recommended hard limit: 60. 0 = no limit.
    static let maxDurationMinutes = "flowa.maxDurationMinutes"
}

enum Preferences {

    /// Persisted flag that the speech model finished preparing on this Mac.
    /// Cleared automatically when load fails or Repair reinstalls the model.
    static var speechModelInstalled: Bool {
        get { UserDefaults.standard.bool(forKey: PrefKey.firstRunComplete) }
        set { UserDefaults.standard.set(newValue, forKey: PrefKey.firstRunComplete) }
    }

    static func markSpeechModelInstalled() {
        speechModelInstalled = true
    }

    static func markSpeechModelNotInstalled() {
        speechModelInstalled = false
    }


    /// ISO 639-1 code (e.g. "en", "da") or the sentinel "auto".
    static var languageCode: String {
        UserDefaults.standard.string(forKey: PrefKey.language) ?? "en"
    }

    /// Whisper language parameter: nil means auto-detect.
    static var languageForWhisper: String? {
        languageForWhisper(from: languageCode)
    }

    /// Pure mapping used by callers and unit tests.
    static func languageForWhisper(from code: String) -> String? {
        code == "auto" ? nil : code
    }

    /// Persisted device UID, or "default" for the system input.
    /// May be stale if the device was unplugged — use
    /// `AudioDeviceManager.resolveCaptureUID` at record time.
    static var microphoneUID: String {
        UserDefaults.standard.string(forKey: PrefKey.microphone) ?? "default"
    }

    /// Whether the UID means "use system default" (no device override).
    static func isSystemDefaultMicrophone(_ uid: String) -> Bool {
        uid == "default" || uid.isEmpty
    }

    /// Persist a mic choice, rewriting ephemeral aggregates to default.
    static func setMicrophoneUID(_ uid: String) {
        if isSystemDefaultMicrophone(uid) || MicDeviceKind.isEphemeralAggregateUID(uid) {
            UserDefaults.standard.set("default", forKey: PrefKey.microphone)
        } else {
            UserDefaults.standard.set(uid, forKey: PrefKey.microphone)
        }
    }

    /// Recommended hard limit for stability (minutes). Used as the default.
    static let recommendedMaxDurationMinutes: Int = 60

    /// User max recording duration in minutes. `0` means no hard limit.
    /// Defaults to `recommendedMaxDurationMinutes` (1 hour).
    static var maxDurationMinutes: Int {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: PrefKey.maxDurationMinutes) == nil {
                return recommendedMaxDurationMinutes
            }
            return sanitizedMaxDurationMinutes(defaults.integer(forKey: PrefKey.maxDurationMinutes))
        }
        set {
            UserDefaults.standard.set(
                sanitizedMaxDurationMinutes(newValue),
                forKey: PrefKey.maxDurationMinutes
            )
        }
    }

    /// Seconds for capture timers. `nil` = no hard limit.
    static var maxDurationSeconds: TimeInterval? {
        let minutes = maxDurationMinutes
        guard minutes > 0 else { return nil }
        return TimeInterval(minutes * 60)
    }

    /// Clamp user input: 0 (unlimited) or 1…24h in minutes.
    static func sanitizedMaxDurationMinutes(_ raw: Int) -> Int {
        if raw <= 0 { return 0 }
        return min(raw, 24 * 60)
    }

    /// Parse a typed field; invalid / empty → recommended default.
    static func maxDurationMinutes(fromField text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else {
            return recommendedMaxDurationMinutes
        }
        return sanitizedMaxDurationMinutes(value)
    }
}
