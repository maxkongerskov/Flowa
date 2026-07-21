import XCTest
@testable import Flowa

final class RepairTests: XCTestCase {

    func testRelaunchCommandPassesPathAsSeparateArgvNotInterpolated() {
        let path = "/Applications/Flowa Test's App.app"
        let cmd = Repair.relaunchCommand(bundlePath: path, delaySeconds: 1)

        XCTAssertEqual(cmd.executable, "/bin/sh")
        XCTAssertEqual(cmd.arguments.count, 3)
        XCTAssertEqual(cmd.arguments[0], "-c")
        // Script must reference $0, not embed the path (quoting/injection safe).
        XCTAssertTrue(cmd.arguments[1].contains("\"$0\""),
                      "script should open via $0, got: \(cmd.arguments[1])")
        XCTAssertFalse(cmd.arguments[1].contains(path),
                       "path must not be interpolated into the shell script string")
        XCTAssertTrue(cmd.arguments[1].contains("sleep 1"),
                      "script should delay before open")
        XCTAssertTrue(cmd.arguments[1].contains("/usr/bin/open"),
                      "script should invoke open")
        XCTAssertEqual(cmd.arguments[2], path)
        XCTAssertEqual(cmd.bundlePathArgument, path)
    }

    func testRelaunchCommandUsesRequestedDelay() {
        let cmd = Repair.relaunchCommand(bundlePath: "/Apps/Flowa.app", delaySeconds: 2)
        XCTAssertTrue(cmd.arguments[1].contains("sleep 2"))
    }

    func testSpawnDetachedRelaunchStartsLiveProcessViaShippedAPI() {
        // Drive the real spawnDetachedRelaunch entry point (not a reimplementation).
        // Long delay so open never fires during the test; we terminate the child.
        let path = "/Applications/Flowa-Nonexistent-Repair-Test.app"
        guard let task = Repair.spawnDetachedRelaunch(bundlePath: path, delaySeconds: 60) else {
            XCTFail("spawnDetachedRelaunch returned nil")
            return
        }
        XCTAssertTrue(task.isRunning,
                      "relaunch helper must be a live OS process before NSApp.terminate")
        task.terminate()
        task.waitUntilExit()
        XCTAssertFalse(task.isRunning)
    }

    func testResetSpeechModelInstallWithoutCacheWipeOnlyTouchesFlag() {
        Preferences.markSpeechModelInstalled()
        Repair.resetSpeechModelInstall(clearCache: false)
        XCTAssertFalse(Preferences.speechModelInstalled)
        Preferences.markSpeechModelInstalled()
    }
}
