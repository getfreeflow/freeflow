import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var stats = StatsStore.shared
    @ObservedObject private var credentials = CredentialStore.shared

    @State private var query = ""

    var body: some View {
        Group {
            if preferences.hasOnboarded {
                main
            } else {
                setupPrompt
            }
        }
        .frame(width: 380)
        .background(Theme.popover)
    }

    /// Setup happens in a real window, so the popover just points at it.
    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text("Finish setting up")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)
            Text("Pick your keys, choose a speech model and grant access, and you're dictating.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open setup") { MainWindowOpener.open() }
                .buttonStyle(ShButtonStyle(variant: .primary, size: .md, fullWidth: true))

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm, fullWidth: true))
        }
        .padding(Theme.Space.lg)
    }

    // MARK: - Main

    private var main: some View {
        VStack(spacing: 0) {
            header
            ShSeparator()

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                status

                if let warning = controller.lastWarning {
                    banner(warning, tone: .warning, symbol: "exclamationmark.triangle.fill")
                }
                if !controller.hotkeyActive {
                    permissionsBanner
                }

                statsRow
                historySection
            }
            .padding(Theme.Space.lg)

            ShSeparator()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
            Text("FreeFlow")
                .font(Theme.Typography.heading)
            Spacer()
            ShBadge(text: badgeText, tone: badgeTone)
        }
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }

    private var status: some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                Circle()
                    .fill(controller.phase == .recording ? Theme.destructive.opacity(0.14) : Theme.muted)
                    .frame(width: 36, height: 36)

                if controller.phase == .recording {
                    LevelMeter(level: controller.level)
                } else if controller.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.statusText)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 0)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: "\(stats.totalWords)", label: "words")
            divider
            stat(value: "\(stats.totalDictations)", label: "dictations")
            divider
            stat(value: stats.timeSavedDescription, label: "saved")
        }
        .padding(.vertical, Theme.Space.md)
        .background(Theme.muted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 24)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                ShSectionLabel(text: "History")
                Spacer()
                if !history.entries.isEmpty {
                    Button("Clear") { history.clear() }
                        .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                        .help("Clears everything except pinned entries")
                }
            }

            if history.entries.isEmpty {
                Text("Nothing yet. Hold \(preferences.dictationKey.label) and say something.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.vertical, Theme.Space.sm)
            } else {
                if history.entries.count > 4 {
                    searchField
                }

                let results = history.search(query)
                if results.isEmpty {
                    Text("No matches.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.vertical, Theme.Space.sm)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(results.prefix(20)) { entry in
                                HistoryRow(entry: entry)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.small)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: - Banners

    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            banner(
                "FreeFlow can't see your keyboard. Grant Accessibility and Input Monitoring.",
                tone: .danger,
                symbol: "lock.fill"
            )
            HStack(spacing: Theme.Space.sm) {
                Button("Open Settings") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                Button("Retry") { controller.restartHotkey() }
                    .buttonStyle(ShButtonStyle(variant: .secondary, size: .sm))
            }
        }
    }

    private func banner(_ message: String, tone: ShBadge.Tone, symbol: String) -> some View {
        let color = tone == .danger ? Theme.destructive : Theme.warning
        return HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(message)
                .font(Theme.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(Theme.Space.sm)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.sm) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    // MARK: - Derived

    private var badgeText: String {
        switch controller.phase {
        case .recording: return controller.mode == .command ? "Command" : "Recording"
        case .transcribing, .polishing: return "Working"
        case .preparingModel: return "Loading"
        case .failed: return "Error"
        case .idle: return controller.modelReady ? "Ready" : "Idle"
        }
    }

    private var badgeTone: ShBadge.Tone {
        switch controller.phase {
        case .recording, .failed: return .danger
        case .transcribing, .polishing, .preparingModel: return .warning
        case .idle: return controller.modelReady ? .success : .neutral
        }
    }

    private var hint: String {
        if controller.phase == .recording { return "Press esc to cancel" }
        if !credentials.hasKey { return "No Groq key, inserting raw transcripts" }
        if preferences.commandKey != .off {
            return "Hold \(preferences.dictationKey.label) to talk · \(preferences.commandKey.label) for commands"
        }
        return "Hold \(preferences.dictationKey.label) to talk, or tap to lock on"
    }
}

// MARK: - History row

private struct HistoryRow: View {
    let entry: DictationEntry
    @ObservedObject private var history = HistoryStore.shared
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(entry.appName) · \(entry.date.formatted(.relative(presentation: .numeric)))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 0)

            if hovering || entry.pinned || copied {
                HStack(spacing: 2) {
                    iconButton(entry.pinned ? "pin.fill" : "pin", help: entry.pinned ? "Unpin" : "Pin") {
                        history.togglePin(entry)
                    }
                    iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                    iconButton("trash", help: "Delete") {
                        history.remove(entry)
                    }
                }
            }
        }
        .padding(Theme.Space.sm)
        .background(hovering ? Theme.accent : Theme.muted.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .onHover { hovering = $0 }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.mutedForeground)
        .help(help)
    }
}
