import AppKit
import SwiftUI

// MARK: - Controller

/// The recording overlay. It lives in the notch: at rest it's exactly the notch's
/// size and invisible against it, and it grows out of it while you record.
///
/// Never takes key status. If it did, the frontmost app would lose focus and
/// dictated text would land in the overlay instead of where you were typing.
@MainActor
final class HUDController: ObservableObject {
    static let shared = HUDController()

    /// False shrinks the shape back into the notch.
    @Published private(set) var isShown = false
    @Published private(set) var notch = NotchGeometry.current()

    private var panel: NotchPanel?
    private var wantsShown = false
    private var orderOutWork: DispatchWorkItem?

    /// Room for the largest state plus its shadow.
    private static let canvas = NSSize(width: 380, height: 110)

    func show(controller: DictationController) {
        NotchMenuController.shared.hide()
        orderOutWork?.cancel()
        wantsShown = true

        let panel = self.panel ?? makePanel(controller: controller)
        self.panel = panel

        guard !panel.isVisible else {
            isShown = true
            return
        }

        notch = NotchGeometry.current()
        isShown = false
        panel.setFrame(notch.windowFrame(Self.canvas), display: false)
        panel.orderFrontRegardless()
        // A runloop later, so SwiftUI lays out the collapsed size first and grows
        // out of it rather than appearing fully formed.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsShown else { return }
            self.isShown = true
        }
    }

    func hide() {
        wantsShown = false
        guard let panel, panel.isVisible else { return }
        isShown = false
        panel.ignoresMouseEvents = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wantsShown else { return }
            self.panel?.orderOut(nil)
        }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Clicks pass straight through unless the overlay has buttons on it.
    fileprivate func setInteractive(_ interactive: Bool) {
        panel?.ignoresMouseEvents = !interactive
    }

    private func makePanel(controller: DictationController) -> NotchPanel {
        let panel = NotchPanel.make(size: Self.canvas, acceptsKey: false)
        panel.ignoresMouseEvents = true
        panel.host(
            RecordingHUD()
                .environmentObject(controller)
                .environmentObject(self)
        )
        return panel
    }
}

// MARK: - View

struct RecordingHUD: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var hud: HUDController

    /// How far the shape reaches past each side of the notch.
    private let ear: CGFloat = 52
    private let shoulder: CGFloat = 6

    /// Only a latched take gets buttons. While the key is held there is nothing to
    /// decide (letting go inserts), so the controls would just be noise.
    private var showsControls: Bool {
        controller.phase == .recording && controller.isLatched
    }

    /// Height of the row that drops below the notch, or zero when the state fits
    /// in the ears either side of it.
    private var rowHeight: CGFloat {
        if showsControls { return 34 }
        switch controller.phase {
        case .failed: return 42
        case .idle: return controller.lastOutcome == .inserted ? 0 : 30
        default: return 0
        }
    }

    private var shapeSize: CGSize {
        let notch = hud.notch.size
        guard hud.isShown else {
            return CGSize(width: notch.width + shoulder * 2, height: hud.notch.isReal ? notch.height : 0)
        }
        return CGSize(width: notch.width + (ear + shoulder) * 2, height: notch.height + rowHeight)
    }

    private struct AnimationKey: Equatable {
        let size: CGSize
        let shown: Bool
    }

    var body: some View {
        let size = shapeSize
        let dropped = hud.isShown && rowHeight > 0
        let shape = NotchShape(topRadius: shoulder, bottomRadius: dropped ? 16 : 10)

        VStack(spacing: 0) {
            ears.frame(height: hud.notch.size.height)
            if rowHeight > 0 {
                row.frame(height: rowHeight)
            }
        }
        .padding(.horizontal, shoulder)
        .frame(width: size.width, height: size.height, alignment: .top)
        .opacity(hud.isShown ? 1 : 0)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(dropped ? 0.3 : 0), radius: 10, y: 4)
        // Grows on a spring and tucks away faster than it came out.
        .animation(
            hud.isShown ? .spring(response: 0.36, dampingFraction: 0.8) : .easeIn(duration: 0.2),
            value: AnimationKey(size: size, shown: hud.isShown)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: showsControls, initial: true) { _, interactive in
            hud.setInteractive(interactive)
        }
    }

    // MARK: Ears

    private var ears: some View {
        HStack(spacing: 0) {
            leftEar.frame(width: ear)
            Spacer(minLength: hud.notch.size.width)
            rightEar.frame(width: ear)
        }
    }

    @ViewBuilder
    private var leftEar: some View {
        switch controller.phase {
        case .recording:
            LiveDot()
        case .transcribing, .polishing, .preparingModel:
            FreeFlowMark(height: 11).foregroundStyle(.white.opacity(0.5))
        case .failed:
            Icon(.alert, size: 13).foregroundStyle(NotchPalette.caution)
        case .idle:
            switch controller.lastOutcome {
            case .inserted:
                FreeFlowMark(height: 11).foregroundStyle(.white.opacity(0.5))
            case .copied:
                Icon(.clipboardCheck, size: 13).foregroundStyle(.white.opacity(0.85))
            case .discarded:
                Icon(.history, size: 13).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var rightEar: some View {
        switch controller.phase {
        case .recording where controller.isLatched:
            Icon(.lock, size: 11).foregroundStyle(.white.opacity(0.45))
        case .recording:
            WaveBars(level: controller.level, barCount: 7)
                .frame(width: 30, height: 13)
        case .transcribing, .polishing, .preparingModel:
            PulsingDots()
        case .idle where controller.lastOutcome == .inserted:
            Icon(.check, size: 13, strokeWidth: 2.6).foregroundStyle(NotchPalette.good)
        default:
            EmptyView()
        }
    }

    // MARK: Row

    @ViewBuilder
    private var row: some View {
        if showsControls {
            HStack {
                circleButton(.x, prominent: false, help: "Don't insert (kept in History)") {
                    controller.discardFromOverlay()
                }
                Spacer()
                WaveBars(level: controller.level, barCount: 13)
                    .frame(width: 70, height: 15)
                Spacer()
                circleButton(.check, prominent: true, help: "Stop and insert") {
                    controller.acceptFromOverlay()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        } else if case .failed(let message) = controller.phase {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        } else {
            Text(controller.lastOutcome == .copied ? "Copied to clipboard" : "Saved to History")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, 6)
        }
    }

    private func circleButton(
        _ icon: Lucide,
        prominent: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Icon(icon, size: 11, strokeWidth: 2.6)
                .foregroundStyle(prominent ? Color.black : .white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(prominent ? Color.white : Color.white.opacity(0.16)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

// MARK: - Pieces

/// The recording light. Breathes rather than blinks.
private struct LiveDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(NotchPalette.live)
                .frame(width: 7, height: 7)
                .opacity(0.6 + 0.4 * (sin(time * 3) * 0.5 + 0.5))
        }
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
struct WaveBars: View {
    let level: Float
    var barCount = 11
    var barWidth: CGFloat = 2

    @State private var state = WaveState()

    var body: some View {
        // No `minimumInterval`. Capping this at 30fps was half the choppiness on a
        // 120Hz display.
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let energy = advance(to: time)

                let spacing = (size.width - CGFloat(barCount) * barWidth)
                    / CGFloat(max(barCount - 1, 1))

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
        let taper = centre > 0 ? 1 - (abs(phase - centre) / centre) * 0.42 : 1

        let minimum: CGFloat = 2.5
        let span = (maximum - minimum) * CGFloat(unit * energy * taper)
        return minimum + max(0, span)
    }
}

struct PulsingDots: View {
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
