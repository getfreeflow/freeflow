import AppKit
import SwiftUI

struct DashboardView: View {
    @Binding var section: AppSection

    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var stats = StatsStore.shared

    @State private var query = ""
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    @State private var inputGranted = Permissions.inputMonitoringGranted

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                PageHeader(title: greeting, subtitle: subtitle)
                blockers
                statRow
                tip
                feed
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(poll) { _ in
            micGranted = Permissions.microphoneGranted
            axGranted = Permissions.accessibilityGranted
            inputGranted = Permissions.inputMonitoringGranted
        }
    }

    // MARK: - Blockers

    /// macOS ties these grants to the app's code signature, so an unsigned rebuild
    /// silently drops them. Without this banner the app just does nothing when you
    /// hold the key, with no explanation anywhere.
    @ViewBuilder
    private var blockers: some View {
        let missing = missingRequirements
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.destructive)
                    Text("Dictation can't run yet")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(missing, id: \.title) { item in
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            Image(systemName: "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.destructive)
                                .padding(.top, 3)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(Theme.Typography.bodyMedium)
                                    .foregroundStyle(Theme.foreground)
                                Text(item.detail)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: Theme.Space.md)

                            Button(item.actionLabel, action: item.action)
                                .buttonStyle(ShButtonStyle(variant: .secondary, size: .sm))
                        }
                    }
                }

                HStack(spacing: Theme.Space.sm) {
                    Button("Re-check now") { controller.restartHotkey() }
                        .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
                    Text("After granting access in System Settings, quit FreeFlow and open it again. macOS often won't apply the change until you do.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.destructive.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.destructive.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private struct Requirement {
        let title: String
        let detail: String
        let actionLabel: String
        let action: () -> Void
    }

    private var missingRequirements: [Requirement] {
        var items: [Requirement] = []

        if !micGranted {
            items.append(Requirement(
                title: "Microphone access",
                detail: Permissions.microphoneWasDenied
                    ? "This was refused earlier, and macOS won't ask a second time. Switch FreeFlow on under Privacy & Security › Microphone."
                    : "Without it there's no audio to transcribe.",
                actionLabel: Permissions.microphoneWasDenied ? "Open Settings" : "Grant",
                action: { Permissions.resolveMicrophone { micGranted = $0 } }
            ))
        }
        if !inputGranted {
            items.append(Requirement(
                title: "Input Monitoring",
                detail: "This is what lets FreeFlow notice your trigger key being held.",
                actionLabel: "Open",
                action: {
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
            ))
        }
        if !axGranted {
            items.append(Requirement(
                title: "Accessibility",
                detail: "Needed to place text into whichever app you're typing in.",
                actionLabel: "Open",
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            ))
        }
        if !controller.hotkeyActive {
            items.append(Requirement(
                title: "Keyboard listener isn't running",
                detail: "macOS refused the event tap, usually because one of the permissions above is missing, or was reset when the app was rebuilt.",
                actionLabel: "Retry",
                action: { controller.restartHotkey() }
            ))
        }
        if preferences.dictationKey == .off {
            items.append(Requirement(
                title: "No dictation key assigned",
                detail: "Pick a trigger key in Settings.",
                actionLabel: "Settings",
                action: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            ))
        }
        return items
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var subtitle: String {
        controller.modelReady
            ? "Hold \(preferences.dictationKey.label) anywhere on your Mac and start talking."
            : "Getting the speech model ready. This only happens once."
    }

    // MARK: - Stats

    private var statRow: some View {
        HStack(spacing: Theme.Space.md) {
            tile(stats.formattedTotalWords, "words spoken", "text.word.spacing")
            tile("\(stats.averageWordsPerMinute)", "words a minute", "gauge.medium")
            tile("\(stats.currentStreak)", stats.currentStreak == 1 ? "day running" : "days running", "flame")
            tile(stats.timeSavedDescription, "not spent typing", "clock.arrow.circlepath")
        }
    }

    private func tile(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.mutedForeground)
            Text(value)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Contextual tip

    @ViewBuilder
    private var tip: some View {
        if !CredentialStore.shared.hasKey {
            tipCard(
                icon: "wand.and.stars",
                title: "You're getting raw transcripts",
                body: "Without an API key, whatever you say goes in exactly as heard, every \"um\" included. A free Groq key turns that into finished text.",
                action: "Add a key",
                isSettings: true
            )
        } else if StyleStore.shared.rules.filter({ $0.enabled }).isEmpty {
            tipCard(
                icon: "textformat",
                title: "Every app is getting the same voice",
                body: "A quick note to a coworker and a paragraph in a document shouldn't read the same way. Style rules let it adjust per app.",
                action: "Set up rules",
                isSettings: false,
                destination: .style
            )
        } else if history.entries.count > 3 && SnippetsStore.shared.snippets.isEmpty {
            tipCard(
                icon: "scissors",
                title: "Stop repeating yourself",
                body: "If you keep dictating the same address, link or block of boilerplate, turn it into a snippet and say it in two words instead.",
                action: "Make a snippet",
                isSettings: false,
                destination: .snippets
            )
        }
    }

    private func tipCard(
        icon: String,
        title: String,
        body: String,
        action: String,
        isSettings: Bool,
        destination: AppSection? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.foreground)
                .frame(width: 30, height: 30)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.foreground)
                Text(body)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Space.md)

            if isSettings {
                SettingsLink {
                    Text(action)
                        .font(Theme.Typography.captionMedium)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Theme.primary)
                        .foregroundStyle(Theme.primaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if let destination {
                Button(action) { section = destination }
                    .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.muted.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Feed

    private var feed: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Recent")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                if !history.entries.isEmpty {
                    SearchField(placeholder: "Search what you've said", text: $query)
                }
            }

            let results = history.search(query)

            if history.entries.isEmpty {
                EmptyState(
                    icon: "mic",
                    title: "Nothing here yet",
                    message: "Put your cursor anywhere (a message box, a document, a search field) and hold \(preferences.dictationKey.label) and say something."
                )
            } else if results.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "Nothing matches",
                    message: "No dictation contains “\(query)”."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(groups(of: results), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.title.uppercased())
                                .font(Theme.Typography.caption)
                                .tracking(0.6)
                                .foregroundStyle(Theme.mutedForeground)
                                .padding(.horizontal, Theme.Space.lg)
                                .padding(.top, Theme.Space.md)
                                .padding(.bottom, 6)

                            ForEach(group.entries) { entry in
                                DictationRow(entry: entry)
                                if entry.id != group.entries.last?.id {
                                    Divider().overlay(Theme.border)
                                }
                            }
                        }
                    }
                }
                .background(Theme.muted.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    private struct Group {
        let title: String
        let entries: [DictationEntry]
    }

    private func groups(of entries: [DictationEntry]) -> [Group] {
        let calendar = Calendar.current
        var buckets: [(String, [DictationEntry])] = []

        for entry in entries.prefix(60) {
            let label: String
            if calendar.isDateInToday(entry.date) {
                label = "Today"
            } else if calendar.isDateInYesterday(entry.date) {
                label = "Yesterday"
            } else {
                label = entry.date.formatted(.dateTime.weekday(.wide).month().day())
            }

            if let index = buckets.firstIndex(where: { $0.0 == label }) {
                buckets[index].1.append(entry)
            } else {
                buckets.append((label, [entry]))
            }
        }
        return buckets.map { Group(title: $0.0, entries: $0.1) }
    }
}

// MARK: - Row

private struct DictationRow: View {
    let entry: DictationEntry
    @ObservedObject private var history = HistoryStore.shared
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            Text(entry.date.formatted(date: .omitted, time: .shortened).lowercased())
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 62, alignment: .leading)
                .padding(.top, 1)

            Text(entry.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: Theme.Space.md)

            HStack(spacing: 2) {
                if entry.pinned || hovering {
                    icon(entry.pinned ? "pin.fill" : "pin", "Pin") { history.togglePin(entry) }
                }
                if hovering || copied {
                    icon(copied ? "checkmark" : "doc.on.doc", "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    }
                    icon("trash", "Delete") { history.remove(entry) }
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, 11)
        .background(hovering ? Theme.accent.opacity(0.6) : .clear)
        .onHover { hovering = $0 }
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.mutedForeground)
        .help(help)
    }
}
