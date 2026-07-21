// Repair.swift
// Flowa
//
// Self-repair entry points:
//   • Permissions — reset TCC, re-register LaunchServices, relaunch
//   • Speech model — wipe weights + first-run flag so install runs again
//   • Full — both
//
// Relaunch is spawned as a live child process *before* terminate so it
// survives app exit (GCD asyncAfter does not).

import Foundation
import AppKit

enum Repair {

    /// What a repair pass should fix.
    struct Options: OptionSet, Equatable {
        let rawValue: Int

        static let permissions = Options(rawValue: 1 << 0)
        static let speechModel = Options(rawValue: 1 << 1)
        static let all: Options = [.permissions, .speechModel]
    }

    /// Configuration for the detached relaunch helper.
    /// Path is always a separate argv element (`$0` inside the script),
    /// never interpolated into a shell-quoted string.
    struct RelaunchCommand: Equatable {
        let executable: String
        let arguments: [String]

        /// The bundle path argument (last argv after `-c` script).
        var bundlePathArgument: String { arguments.last ?? "" }
    }

    /// Pure builder — unit-tested. `delaySeconds` is the sleep before open.
    static func relaunchCommand(bundlePath: String, delaySeconds: Int = 1) -> RelaunchCommand {
        // sh -c 'sleep N; exec /usr/bin/open "$0"' <bundlePath>
        // $0 is the path argv — safe for spaces/quotes; no string interpolation of path.
        RelaunchCommand(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "sleep \(delaySeconds); exec /usr/bin/open \"$0\"",
                bundlePath
            ]
        )
    }

    /// Wipe speech-model install state (UserDefaults + optional on-disk cache).
    /// Pure-ish for tests: does not relaunch.
    static func resetSpeechModelInstall(clearCache: Bool = true) {
        Preferences.markSpeechModelNotInstalled()
        if clearCache {
            SpeechModelStore.clearDownloadedModels()
        }
    }

    /// Full repair: optional TCC reset + optional model wipe, then relaunch.
    static func run(options: Options = .all) {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.maxkongerskov.Flowa"
        let bundlePath = Bundle.main.bundlePath

        if options.contains(.permissions) {
            runProcess("/usr/bin/tccutil", ["reset", "Microphone", bundleId])
            runProcess("/usr/bin/tccutil", ["reset", "ListenEvent", bundleId])
            runProcess("/usr/bin/tccutil", ["reset", "Accessibility", bundleId])

            let lsregister = "/System/Library/Frameworks/CoreServices.framework/"
                + "Frameworks/LaunchServices.framework/Support/lsregister"
            runProcess(lsregister, ["-f", bundlePath])
        }

        if options.contains(.speechModel) {
            resetSpeechModelInstall(clearCache: true)
        }

        // Spawn relaunch helper NOW as a real process, then terminate.
        // Must not use DispatchQueue.asyncAfter — that dies with NSApp.terminate.
        _ = spawnDetachedRelaunch(bundlePath: bundlePath)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    /// Convenience: permissions + model (historical single-button behavior, improved).
    static func run() {
        run(options: .all)
    }

    /// Starts the sleep+open helper without waiting. Child outlives this process.
    /// Returns the running `Process` (for tests / diagnostics), or nil on failure.
    @discardableResult
    static func spawnDetachedRelaunch(bundlePath: String, delaySeconds: Int = 1) -> Process? {
        let cmd = relaunchCommand(bundlePath: bundlePath, delaySeconds: delaySeconds)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cmd.executable)
        task.arguments = cmd.arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // Intentionally do not waitUntilExit — helper sleeps then opens.
            return task
        } catch {
            print("[Flowa][repair] relaunch spawn failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func runProcess(_ path: String, _ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("[Flowa][repair] \(path) failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Window focus helper for self-repair UX

extension Notification.Name {
    /// Posted when Flowa needs the main window visible (model install, errors).
    static let flowaShowMainWindow = Notification.Name("flowa.showMainWindow")
}
