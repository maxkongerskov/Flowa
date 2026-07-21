import XCTest
@testable import Flowa

final class PreferencesTests: XCTestCase {

    func testLanguageForWhisperMapsAutoToNil() {
        XCTAssertNil(Preferences.languageForWhisper(from: "auto"))
    }

    func testLanguageForWhisperPassesThroughCodes() {
        XCTAssertEqual(Preferences.languageForWhisper(from: "en"), "en")
        XCTAssertEqual(Preferences.languageForWhisper(from: "da"), "da")
    }

    func testPrefKeyConstantsAreStable() {
        XCTAssertEqual(PrefKey.language, "flowa.language")
        XCTAssertEqual(PrefKey.microphone, "flowa.microphone")
        XCTAssertEqual(PrefKey.colorSchemeDark, "flowa.colorScheme.dark")
        XCTAssertEqual(PrefKey.onboardingComplete, "flowa.onboardingComplete")
        XCTAssertEqual(PrefKey.firstRunComplete, "flowa.firstRunComplete")
        XCTAssertEqual(PrefKey.maxDurationMinutes, "flowa.maxDurationMinutes")
    }

    func testSystemDefaultMicrophoneSentinel() {
        XCTAssertTrue(Preferences.isSystemDefaultMicrophone("default"))
        XCTAssertTrue(Preferences.isSystemDefaultMicrophone(""))
        XCTAssertFalse(Preferences.isSystemDefaultMicrophone("BuiltInMicrophoneDevice"))
    }

    func testMaxDurationSanitization() {
        XCTAssertEqual(Preferences.sanitizedMaxDurationMinutes(60), 60)
        XCTAssertEqual(Preferences.sanitizedMaxDurationMinutes(0), 0)
        XCTAssertEqual(Preferences.sanitizedMaxDurationMinutes(-5), 0)
        XCTAssertEqual(Preferences.sanitizedMaxDurationMinutes(99999), 24 * 60)
        XCTAssertEqual(Preferences.maxDurationMinutes(fromField: "60"), 60)
        XCTAssertEqual(Preferences.maxDurationMinutes(fromField: " 0 "), 0)
        XCTAssertEqual(Preferences.maxDurationMinutes(fromField: ""), Preferences.recommendedMaxDurationMinutes)
        XCTAssertEqual(Preferences.maxDurationMinutes(fromField: "abc"), Preferences.recommendedMaxDurationMinutes)
    }

    func testMaxDurationSecondsNilWhenUnlimited() {
        let old = Preferences.maxDurationMinutes
        defer { Preferences.maxDurationMinutes = old }
        Preferences.maxDurationMinutes = 0
        XCTAssertNil(Preferences.maxDurationSeconds)
        Preferences.maxDurationMinutes = 60
        XCTAssertEqual(Preferences.maxDurationSeconds, 3600)
    }
}
