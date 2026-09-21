import AppKit
import SwiftUI

// MARK: - Status item

/// The menu bar icon. Clicking it drops the panel out of the notch rather than
/// opening a popover under the icon.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var item: NSStatusItem?

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = FreeFlowMark.menuBarImage()
            button.setAccessibilityLabel("FreeFlow")
            button.target = self
            button.action = #selector(toggleMenu)
        }
        self.item = item
    }

    @objc private func toggleMenu() {
        NotchMenuController.shared.toggle()
    }
}

// MARK: - Controller

@MainActor
final class NotchMenuController: ObservableObject {
    static let shared = NotchMenuController()

    @Published private(set) var isShown = false
    @Published private(set) var notch = NotchGeometry.current()

    /// Panel width, shoulders included.
    static let width: CGFloat = 460
    static let shoulder: CGFloat = 8

    private var panel: NotchPanel?
    private var wantsShown = false
    private var orderOutWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var contentHeight: CGFloat = 520
    private var hiddenAt = Date.distantPast

    func toggle() {
        if wantsShown {
            hide()
        } else if Date().timeIntervalSince(hiddenAt) > 0.3 {
            // Clicking the icon while open also counts as a click outside, which
            // has already closed it. Without the gap it would reopen at once.
            show()
        }
    }

    func show() {
        // The notch is busy showing a take.
        guard DictationController.shared.phase != .recording else { return }
        orderOutWork?.cancel()
        wantsShown = true

        let panel = self.panel ?? makePanel()
        self.panel = panel

        if panel.isVisible {
            isShown = true
        } else {
            notch = NotchGeometry.current()
            isShown = false
            resizeWindow()
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsShown else { return }
                self.isShown = true
            }
        }
        // Key without activating the app, so the search field takes typing and
        // whatever you were in stays frontmost underneath.
        panel.makeKey()
        watchForDismissal()
    }

    func hide() {
        guard wantsShown else { return }
        wantsShown = false
        hiddenAt = Date()
        stopWatching()
        guard let panel, panel.isVisible else { return }
        isShown = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wantsShown else { return }
            self.panel?.orderOut(nil)
        }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    /// The window follows the content, so no transparent part of it sits over the
    /// screen swallowing clicks.
    fileprivate func contentHeightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        resizeWindow()
    }

    private func resizeWindow() {
        let size = NSSize(width: Self.width + 48, height: contentHeight + 36)
        panel?.setFrame(notch.windowFrame(size), display: true)
    }

    private func watchForDismissal() {
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }
        if resignObserver == nil, let panel {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        clickMonitor = nil
        resignObserver = nil
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel.make(
            size: NSSize(width: Self.width + 48, height: contentHeight + 36),
            acceptsKey: true
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.host(
            MenuBarPanel()
                .environmentObject(DictationController.shared)
                .environmentObject(Preferences.shared)
                .environmentObject(self)
        )
        return panel
    }
}

// MARK: - Panel

struct MenuBarPanel: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var menu: NotchMenuController
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var stats = StatsStore.shared
    @ObservedObject private var credentials = CredentialStore.shared
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let shape = NotchShape(
            topRadius: NotchMenuController.shoulder,
            bottomRadius: menu.isShown ? 24 : 10
        )

        content
            .frame(width: NotchMenuController.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                }
            )
            .opacity(menu.isShown ? 1 : 0)
            .frame(width: shownSize.width, height: shownSize.height, alignment: .top)
            .background(Color.black)
            .clipShape(shape)
            .shadow(color: .black.opacity(menu.isShown ? 0.35 : 0), radius: 18, y: 8)
            .animation(
                menu.isShown ? .spring(response: 0.42, dampingFraction: 0.84) : .easeIn(duration: 0.2),
                value: menu.isShown
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .onPreferenceChange(HeightKey.self) { height in
                contentHeight = height
                menu.contentHeightChanged(height)
            }
            .onExitCommand { menu.hide() }
    }

    /// Collapsed, it's the notch. Open, it's the full panel.
    private var shownSize: CGSize {
        if menu.isShown {
            return CGSize(width: NotchMenuController.width, height: max(contentHeight, 1))
        }
        let notch = menu.notch
        return CGSize(
            width: notch.size.width + NotchMenuController.shoulder * 2,
            height: notch.isReal ? notch.size.height : 0
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            notchBand
            if preferences.hasOnboarded {
                main
            } else {
                setup
            }
        }
        .padding(.horizontal, NotchMenuController.shoulder)
    }

    /// The strip level with the notch. Name on one side, state on the other, and
    /// the notch itself in between.
    private var notchBand: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                FreeFlowMark(height: 12)
                Text("FreeFlow")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(NotchPalette.text)

            Spacer(minLength: menu.notch.size.width + 12)

            StatusPill(text: badgeText, color: badgeColor)
        }
        .padding(.horizontal, 12)
        .frame(height: menu.notch.size.height)
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                statusCard

                if let warning = controller.lastWarning {
                    banner(warning, icon: .alert, tint: NotchPalette.caution)
                }
                if !controller.hotkeyActive {
                    permissionsBanner
                }

                statsRow
                historySection
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Rectangle().fill(NotchPalette.hairline).frame(height: 1)
            footer
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NotchPalette.surface)

                if controller.phase == .recording {
                    WaveBars(level: controller.level, barCount: 5, barWidth: 2.5)
                        .frame(width: 20, height: 16)
                } else if controller.isBusy {
                    PulsingDots()
                } else {
                    Icon(.mic, size: 17).foregroundStyle(NotchPalette.secondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                headline
                Text(subline)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchPalette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var headline: some View {
        if controller.phase == .idle, controller.modelReady {
            HStack(spacing: 6) {
                Text("Hold")
                KeyCap(preferences.dictationKey.label)
                Text("to talk")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(NotchPalette.text)
        } else {
            Text(controller.statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NotchPalette.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subline: String {
        switch controller.phase {
        case .recording:
            return controller.isLatched
                ? "Tap \(controller.triggerLabel) again to finish"
                : "Let go to insert · esc to cancel"
        case .idle where controller.modelReady:
            var parts = ["Double-tap to lock it on"]
            if preferences.commandKey != .off {
                parts.append("\(preferences.commandKey.label) for commands")
            }
            if !credentials.hasKey {
                parts.append("no Groq key, raw transcripts")
            }
            return parts.joined(separator: " · ")
        default:
            return credentials.hasKey ? "Cleanup is on" : "No Groq key, inserting raw transcripts"
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(stats.totalWords.formatted(), "words")
            verticalHairline
            stat("\(stats.totalDictations)", "dictations")
            verticalHairline
            stat(stats.timeSavedDescription, "saved")
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NotchPalette.surface)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchPalette.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NotchPalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalHairline: some View {
        Rectangle().fill(NotchPalette.hairline).frame(width: 1, height: 26)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchPalette.text)
                if !history.entries.isEmpty {
                    Text("\(history.entries.count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(NotchPalette.tertiary)
                }
                Spacer()
                if !history.entries.isEmpty {
                    TextButton(title: "Clear") { history.clear() }
                        .help("Clears everything except pinned entries")
                }
            }

            if history.entries.isEmpty {
                Text("Nothing yet. Hold \(preferences.dictationKey.label) and say something.")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchPalette.secondary)
                    .padding(.vertical, 6)
            } else {
                if history.entries.count > 4 {
                    searchField
                }

                let results = history.search(query)
                if results.isEmpty {
                    Text("No matches.")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchPalette.secondary)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(results.prefix(20)) { entry in
                                HistoryRow(entry: entry)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: 150)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Icon(.search, size: 13).foregroundStyle(NotchPalette.tertiary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(NotchPalette.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Icon(.x, size: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotchPalette.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NotchPalette.surface)
        )
    }

    // MARK: Banners

    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            banner(
                "FreeFlow can't see your keyboard. Grant Accessibility and Input Monitoring.",
                icon: .lock,
                tint: NotchPalette.live
            )
            HStack(spacing: 6) {
                TextButton(title: "Open Settings") { Permissions.openAccessibilitySettings() }
                TextButton(title: "Retry") { controller.restartHotkey() }
            }
        }
    }

    private func banner(_ message: String, icon: Lucide, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(icon, size: 13).padding(.top, 1)
            Text(message)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12))
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(icon: .appWindow, title: "Open FreeFlow") {
                menu.hide()
                MainWindowOpener.open()
            }
            FooterButton(icon: .settings, title: "Settings") {
                menu.hide()
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            FooterButton(icon: .power, title: "Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }

    // MARK: Setup

    /// Setup happens in a real window, so the panel just points at it.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish setting up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NotchPalette.text)
            Text("Pick your keys, choose a speech model and grant access, and you're dictating.")
                .font(.system(size: 12))
                .foregroundStyle(NotchPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                menu.hide()
                MainWindowOpener.open()
            } label: {
                Text("Open setup")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
            }
            .buttonStyle(PressableStyle())

            FooterButton(icon: .power, title: "Quit") { NSApp.terminate(nil) }
        }
        .padding(16)
    }

    // MARK: Derived

    private var badgeText: String {
        switch controller.phase {
        case .recording: return controller.mode == .command ? "Command" : "Listening"
        case .transcribing, .polishing: return "Working"
        case .preparingModel: return "Loading"
        case .failed: return "Error"
        case .idle: return controller.modelReady ? "Ready" : "Idle"
        }
    }

    private var badgeColor: Color {
        switch controller.phase {
        case .recording, .failed: return NotchPalette.live
        case .transcribing, .polishing, .preparingModel: return NotchPalette.caution
        case .idle: return controller.modelReady ? NotchPalette.good : NotchPalette.tertiary
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Pieces

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.82))
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// The trigger key, drawn as a key.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NotchPalette.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(NotchPalette.hairlineStrong, lineWidth: 1)
            )
    }
}

private struct HistoryRow: View {
    let entry: DictationEntry
    @ObservedObject private var history = HistoryStore.shared
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(NotchPalette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if entry.pinned {
                        Icon(.pin, size: 9).foregroundStyle(NotchPalette.secondary)
                    }
                    Text("\(entry.appName) · \(entry.date.formatted(.relative(presentation: .numeric)))")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchPalette.tertiary)
                }
            }

            Spacer(minLength: 0)

            if hovering || copied {
                HStack(spacing: 2) {
                    RowAction(icon: copied ? .check : .copy, help: "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                    RowAction(icon: .pin, help: entry.pinned ? "Unpin" : "Pin", active: entry.pinned) {
                        history.togglePin(entry)
                    }
                    RowAction(icon: .trash, help: "Delete") {
                        history.remove(entry)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? NotchPalette.surfaceHover : NotchPalette.surface)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct RowAction: View {
    let icon: Lucide
    let help: String
    var active = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 12)
                .foregroundStyle(active || hovering ? NotchPalette.text : NotchPalette.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct FooterButton: View {
    let icon: Lucide
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(icon, size: 13)
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(hovering ? NotchPalette.text : NotchPalette.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TextButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? NotchPalette.text : NotchPalette.secondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
