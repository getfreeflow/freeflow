import AppKit
import SwiftUI

// MARK: - Geometry

/// Where the notch is on a screen, and how big.
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let size: CGSize
    /// False on displays without a notch. The UI then draws a tab of its own that
    /// folds up into the top edge instead of hiding behind the real thing.
    let isReal: Bool

    /// The screen under the pointer, since that's the one being looked at.
    static func current() -> NotchGeometry {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        return NotchGeometry(screen: screen)
    }

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            size = CGSize(width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            isReal = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            size = CGSize(width: 160, height: max(menuBar, 24))
            isReal = false
        }
    }

    /// A window of `size` hanging from the top edge, centred on the notch.
    func windowFrame(_ size: NSSize) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Shape

/// The notch's outline: flat along the top edge, flaring into it through two small
/// concave shoulders, straight sides, rounded bottom corners.
///
/// Drawn at the notch's own size it disappears against the real one, which is what
/// lets everything built on it look like the notch itself growing.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = max(0, min(bottomRadius, (rect.width - top * 2) / 2, rect.height - top))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Window

/// Borderless, transparent, above the menu bar and on every Space.
final class NotchPanel: NSPanel {
    private(set) var acceptsKey = false

    static func make(size: NSSize, acceptsKey: Bool) -> NotchPanel {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.acceptsKey = acceptsKey
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // drawn in SwiftUI so it follows the shape
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    /// AppKit keeps windows out of the menu bar. This one belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func host<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [] // the controller owns the window size
        // NSHostingView paints an opaque background of its own otherwise, which
        // shows as a rectangle around the shape.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
    }
}

// MARK: - Palette

/// Everything that lives in the notch is black like the notch. Surfaces step up
/// from it in small amounts so the result stays calm rather than glowing.
enum NotchPalette {
    static let surface = Color(white: 0.075)
    static let surfaceHover = Color(white: 0.11)
    static let surfaceRaised = Color(white: 0.15)
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.14)

    static let text = Color(white: 0.96)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.42)

    static let live = Color(nsColor: NSColor(hex: 0xFF453A))
    static let good = Color(nsColor: NSColor(hex: 0x30D158))
    static let caution = Color(nsColor: NSColor(hex: 0xFFB340))
}

/// A press that shrinks slightly, for small controls with no other chrome.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
