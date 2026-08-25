import AppKit
import SwiftUI

enum SidebarGroup: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case tuning = "Tuning"
    case review = "Review"

    var id: String { rawValue }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dictation, meetings, scratchpad
    case vocabulary, snippets, style, actions
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:  return "Dictation"
        case .meetings:   return "Meetings"
        case .scratchpad: return "Scratchpad"
        case .vocabulary: return "Vocabulary"
        case .snippets:   return "Snippets"
        case .style:      return "Style"
        case .actions:    return "Actions"
        case .insights:   return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .dictation:  return "mic"
        case .meetings:   return "record.circle"
        case .scratchpad: return "note.text"
        case .vocabulary: return "book.closed"
        case .snippets:   return "scissors"
        case .style:      return "textformat"
        case .actions:    return "wand.and.stars"
        case .insights:   return "chart.bar"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .dictation, .meetings, .scratchpad:
            return .capture
        case .vocabulary, .snippets, .style, .actions:
            return .tuning
        case .insights:
            return .review
        }
    }

    static func sections(in group: SidebarGroup) -> [AppSection] {
        allCases.filter { $0.group == group }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    @State private var section: AppSection = .dictation

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
                .frame(width: 224)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        }
        .background(Theme.background)
        .frame(minWidth: 940, minHeight: 620)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .dictation:  DashboardView(section: $section)
        case .meetings:   MeetingsView()
        case .scratchpad: ScratchpadView()
        case .vocabulary: VocabularyView()
        case .snippets:   SnippetsView()
        case .style:      StyleView()
        case .actions:    ActionsView()
        case .insights:   InsightsView()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var section: AppSection
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @ObservedObject private var recorder = MeetingRecorder.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                Text("FreeFlow")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SidebarGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(Theme.mutedForeground.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.bottom, 3)

                            ForEach(AppSection.sections(in: group)) { item in
                                SidebarItem(
                                    section: item,
                                    selected: section == item,
                                    badge: item == .meetings && recorder.isRecording ? "REC" : nil
                                ) {
                                    section = item
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 12)

            ModelStatusCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            VStack(spacing: 2) {
                SettingsLink {
                    sidebarRowLabel("Settings", icon: "gearshape")
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                } label: {
                    sidebarRowLabel("Help", icon: "questionmark.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private func sidebarRowLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(title).font(Theme.Typography.body)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.mutedForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

}

private struct SidebarItem: View {
    let section: AppSection
    let selected: Bool
    var badge: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(section.title)
                    .font(Theme.Typography.body)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.destructive)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(selected ? Theme.foreground : Theme.mutedForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if selected { return Theme.accent }
        return hovering ? Theme.muted.opacity(0.7) : .clear
    }
}

// MARK: - Shared page chrome

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            Spacer(minLength: Theme.Space.lg)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Theme.mutedForeground)
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.foreground)
            Text(message)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.mutedForeground)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.small)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: 240)
        .background(Theme.muted.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}
