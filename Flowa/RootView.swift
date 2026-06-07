// RootView.swift
// Flowa
//
// Single-screen shell. RootView just hosts HomeView at the locked
// window dimensions defined by FlowaApp.

import SwiftUI

struct RootView: View {
    @ObservedObject var hotkey: GlobalHotkey
    @ObservedObject var conflict: FnConflictDetector
    @ObservedObject var accessibility: AccessibilityChecker

    var body: some View {
        HomeView(
            hotkey: hotkey,
            conflict: conflict,
            accessibility: accessibility
        )
    }
}
