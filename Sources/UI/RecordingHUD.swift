import AppKit
import SwiftUI

// MARK: - Panel

/// Never takes focus. If it became key the frontmost app would change and dictated
/// text would land in the overlay instead of wherever the user was typing. A
/// `.nonactivatingPanel` still receives clicks, so the buttons work anyway.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

@MainActor
final class HUDController {
    static let shared = HUDController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    /// Kept tight to the pill. The panel takes mouse events so its buttons work,
    /// which makes any transparent margin a dead zone for clicks near the screen
    /// edge. The pill is centred here, so height also controls how low it sits.
    private static let size = NSSize(width: 200, height: 34)
    /// From `visibleFrame`, so this clears the Dock when the Dock is showing.
    private static let bottomInset: CGFloat = 4

    func show(controller: DictationController) {
        hideWorkItem?.cancel()

        if panel == nil {
            let panel = HUDPanel(
                contentRect: NSRect(origin: .zero, size: Self.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = false // drawn in SwiftUI so it follows the pill shape
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false // the discard / accept buttons need clicks
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]

            // NSHostingView paints an opaque background of its own, which shows up
            // as a black rectangle behind the rounded pill.
            let hosting = NSHostingView(
                rootView: RecordingHUD().environmentObject(controller)
            )
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting

            self.panel = panel
        }

        guard let panel else { return }

        let isAlreadyVisible = panel.isVisible
        reposition(rising: !isAlreadyVisible)

        if !isAlreadyVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            // Fade and drift up into place rather than snapping on.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(restingFrame(), display: true)
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        hideWorkItem?.cancel()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: - Placement

    private func restingFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        return NSRect(
            x: visible.midX - Self.size.width / 2,
            y: visible.minY + Self.bottomInset,
            width: Self.size.width,
            height: Self.size.height
        )
    }

    private func reposition(rising: Bool) {
        guard let panel else { return }
        var frame = restingFrame()
        if rising { frame.origin.y -= 10 } // starting point for the drift up
        panel.setFrame(frame, display: false)
    }
}

// MARK: - View

struct RecordingHUD: View {
    @EnvironmentObject private var controller: DictationController

    /// Only a latched take gets buttons. While the key is held there is nothing to
    /// decide (letting go inserts), so the controls would just be noise.
    private var showsControls: Bool {
        controller.phase == .recording && controller.isLatched
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsControls {
                iconButton("xmark", filled: false, help: "Don't insert (kept in History)") {
                    controller.discardFromOverlay()
                }
            }

            center

            if showsControls {
                iconButton("checkmark", filled: true, help: "Stop and insert") {
                    controller.acceptFromOverlay()
                }
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 24)
        .background(
            Capsule().fill(Color(nsColor: NSColor(hex: 0x1C1C1E)).opacity(0.92))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var center: some View {
        switch controller.phase {
        case .recording:
            WaveBars(level: controller.level)
                .frame(width: 46, height: 13)

        case .transcribing, .polishing, .preparingModel:
            HStack(spacing: 5) {
                PulsingDots()
                Text(busyLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)

        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: 150)
            }
            .padding(.horizontal, 3)

        case .idle:
            switch controller.lastOutcome {
            case .inserted:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)

            case .copied:
                // Nothing visibly happened in the target app, so without this the
                // dictation looks like it vanished.
                label("doc.on.clipboard", "Copied", tint: .white.opacity(0.9))

            case .discarded:
                label("clock.arrow.circlepath", "Saved to History", tint: .white.opacity(0.7))
            }
        }
    }

    private func label(_ symbol: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
    }

    private var busyLabel: String {
        switch controller.phase {
        case .transcribing:   return "Transcribing"
        case .polishing:      return controller.mode == .command ? "Thinking" : "Polishing"
        case .preparingModel: return "Loading model"
        default:              return ""
        }
    }

    private func iconButton(
        _ symbol: String,
        filled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(filled ? Color.white : Color.white.opacity(0.16))
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(filled ? Color(nsColor: NSColor(hex: 0x1C1C1E)) : .white)
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(HUDButtonStyle())
        .help(help)
    }
}

private struct HUDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Smoothing state carried between frames. A reference type in `@State` so mutating
/// it doesn't invalidate the view; `TimelineView` already drives the redraws.
private final class WaveState {
    var smoothedLevel: Double = 0
    var lastFrame: TimeInterval = 0
}

/// Bars that are always in motion.
///
/// Drawn in a `Canvas`, not an `HStack` of `Capsule`s. Resizing a stack of views
/// every frame makes SwiftUI run a full layout pass per frame, which is what made
/// this stutter. A Canvas only rasterises.
///
/// Not a VU meter. Three sine components at unrelated frequencies (a wave
/// travelling across the bars, a slow swell, a fast flutter) keep the pattern from
/// visibly repeating. Mic level only scales how far the bars swing, and is
/// low-pass filtered first so a jump in volume eases in instead of snapping.
private struct WaveBars: View {
    let level: Float

    @State private var state = WaveState()

    private let barCount = 11
    private let barWidth: CGFloat = 2

    var body: some View {
        // No `minimumInterval`. Capping this at 30fps was half the choppiness on a
        // 120Hz display.
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let energy = advance(to: time)

                let spacing = (size.width - CGFloat(barCount) * barWidth)
                    / CGFloat(barCount - 1)

                for index in 0..<barCount {
                    let height = barHeight(index, time, energy, maximum: size.height)
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(.white.opacity(0.92))
                    )
                }
            }
        }
    }

    /// Eases the published level toward its target with a fixed time constant, so
    /// the motion is independent of how often the recorder reports a new value.
    private func advance(to time: TimeInterval) -> Double {
        let delta = state.lastFrame == 0 ? 1.0 / 60.0 : min(time - state.lastFrame, 0.1)
        state.lastFrame = time

        let target = Double(min(max(level, 0), 1))
        let alpha = 1 - exp(-delta / 0.09) // ~90ms to catch up
        state.smoothedLevel += (target - state.smoothedLevel) * alpha

        // Never fully still. Idle bars still drift, they just don't reach as high.
        return 0.30 + state.smoothedLevel * 0.95
    }

    private func barHeight(
        _ index: Int,
        _ time: TimeInterval,
        _ energy: Double,
        maximum: CGFloat
    ) -> CGFloat {
        let phase = Double(index)
        let travelling = sin(time * 3.1 - phase * 0.9)
        let swell = sin(time * 1.7 + phase * 0.35) * 0.7
        let flutter = sin(time * 7.3 + phase * 2.1) * 0.45
        let unit = ((travelling + swell + flutter) / 2.15 + 1) / 2 // 0...1

        // Taper toward the ends so the group reads as a waveform, not a block.
        let centre = Double(barCount - 1) / 2
        let taper = 1 - (abs(phase - centre) / centre) * 0.42

        let minimum: CGFloat = 2.5
        let span = (maximum - minimum) * CGFloat(unit * energy * taper)
        return minimum + max(0, span)
    }
}

private struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(opacity(index, time)))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
    }

    private func opacity(_ index: Int, _ time: TimeInterval) -> Double {
        let phase = Double(index) * 0.6
        return 0.35 + (sin(time * 3.2 + phase) * 0.5 + 0.5) * 0.55
    }
}
