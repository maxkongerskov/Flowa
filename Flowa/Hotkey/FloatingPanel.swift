// FloatingPanel.swift
// Flowa
//
// Borderless NSPanel at the bottom-centre of the active screen that
// appears when listening starts and disappears on commit / cancel.
// Hosts the Flow Bar pill (X · waveform · ✓).
//
// Doesn't steal key focus — user keeps typing into their app.

import AppKit
import SwiftUI

final class FlowaFloatingPanel: NSPanel {

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.alphaValue = 0

        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.contentView = container
        positionAtBottomCentre()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        positionAtBottomCentre()
        // Force-set alpha to 1 immediately as a safety net so the panel
        // is visible even if the animation context misfires.
        self.alphaValue = 1.0
        orderFrontRegardless()
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private func positionAtBottomCentre() {
        // Prefer the screen the cursor is on — NSScreen.main follows key
        // focus, which on multi-monitor setups (e.g. MacBook + Studio
        // Display) routinely puts the pill on the wrong screen. Wispr /
        // Superwhisper both use the cursor's screen, which matches user
        // intent: the pill appears where the user is currently working.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) })
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = self.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 60
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Flow Bar content (the actual pill)
//
// Binds to AudioCapture.level for the waveform — the bars rise and
// fall with the user's voice in real time. Rolling history of the
// last N levels is kept so the bars scroll right-to-left rather than
// all spiking together (looks more "alive").

struct FlowBarContent: View {
    @ObservedObject var audio: AudioCapture
    var onCancel: () -> Void = {}
    var onCommit: () -> Void = {}

    @State private var history: [Float] = Array(repeating: 0, count: 14)
    private let barCount = 14

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white.opacity(0.75))
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 2, height: height(for: i))
                        .animation(.easeOut(duration: 0.08), value: history[i])
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.flowBarBackground)
        )
        .onChange(of: audio.level) { _, newLevel in
            // Push newest level on the right, drop oldest on the left —
            // produces a scrolling waveform rather than uniform spikes.
            history.removeFirst()
            history.append(newLevel)
        }
    }

    /// Map 0...1 audio level to a bar height between 4 and 22 pt.
    private func height(for i: Int) -> CGFloat {
        let level = CGFloat(history[i])
        return 4 + level * 18
    }
}
