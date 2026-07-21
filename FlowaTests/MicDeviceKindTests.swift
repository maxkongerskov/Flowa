import XCTest
import CoreAudio
@testable import Flowa

final class MicDeviceKindTests: XCTestCase {

    func testClassifiesIPhoneModelUIDAsContinuity() {
        let kind = MicDeviceKind.classify(
            name: "Max’s iPhone Microphone",
            modelUID: "iPhone Mic",
            transport: 0,
            uid: "181D41EF-720B-49C2-A1CA-207D00000003"
        )
        XCTAssertEqual(kind, .continuity)
    }

    func testClassifiesCCWDTransportAsContinuity() {
        let kind = MicDeviceKind.classify(
            name: "Some Device",
            modelUID: "",
            transport: MicTransport.continuityWireless,
            uid: "abc"
        )
        XCTAssertEqual(kind, .continuity)
    }

    func testClassifiesUSBStudioAsStandard() {
        let kind = MicDeviceKind.classify(
            name: "Studio Display Microphone",
            modelUID: "Studio Display Audio Control:05AC:1114",
            transport: kAudioDeviceTransportTypeUSB,
            uid: "AppleUSBAudioEngine:Apple Inc.:Studio Display:xyz"
        )
        XCTAssertEqual(kind, .standard)
    }

    func testDisplayNameAddsSpeakNearPhoneForContinuity() {
        let label = MicDeviceKind.displayName(name: "Max’s iPhone Microphone", kind: .continuity)
        XCTAssertTrue(label.contains("speak near phone"))
        XCTAssertTrue(label.contains("iPhone"))
    }

    func testDisplayNameUnchangedForStandard() {
        let label = MicDeviceKind.displayName(name: "Studio Display Microphone", kind: .standard)
        XCTAssertEqual(label, "Studio Display Microphone")
    }

    func testEphemeralAggregateUID() {
        XCTAssertTrue(MicDeviceKind.isEphemeralAggregateUID("CADefaultDeviceAggregate-852-0"))
        XCTAssertFalse(MicDeviceKind.isEphemeralAggregateUID(
            "AppleUSBAudioEngine:Apple Inc.:Studio Display:00008030:6,7"
        ))
    }
}
