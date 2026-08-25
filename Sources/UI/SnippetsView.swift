import SwiftUI

struct SnippetsView: View {
    @ObservedObject private var store = SnippetsStore.shared

    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Snippets",
                subtitle: "Say a short phrase, get the whole block of text."
            )

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("New snippet")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)

                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        VStack(alignment: .leading, spacing: 4) {
                            ShSectionLabel(text: "When I say")
                            TextField("my email", text: $trigger)
                                .textFieldStyle(ShTextFieldStyle())
                        }
                        .frame(width: 200)

                        VStack(alignment: .leading, spacing: 4) {
                            ShSectionLabel(text: "Insert")
                            TextField("hello@example.com", text: $expansion, axis: .vertical)
                                .textFieldStyle(ShTextFieldStyle())
                                .lineLimit(1...4)
                        }
                    }

                    HStack {
                        Text("Expanded before cleanup, so the result still gets formatted to fit the app.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.mutedForeground)
                        Spacer()
                        Button("Add snippet", action: add)
                            .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
                            .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty
                                      || expansion.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if store.snippets.isEmpty {
                EmptyState(
                    icon: "scissors",
                    title: "No snippets yet",
                    message: "Good candidates: your email address, a calendar link, a standup template, your mailing address."
                )
            } else {
                VStack(spacing: Theme.Space.sm) {
                    ForEach(store.snippets) { snippet in
                        SnippetRow(snippet: snippet)
                    }
                }
            }
        }
    }

    private func add() {
        store.add(trigger: trigger, expansion: expansion)
        trigger = ""
        expansion = ""
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    @ObservedObject private var store = SnippetsStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.opening").font(.system(size: 9))
                    Text(snippet.trigger)
                        .font(Theme.Typography.bodyMedium)
                }
                .foregroundStyle(Theme.foreground)

                Text(snippet.expansion)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { snippet.enabled },
                set: { var copy = snippet; copy.enabled = $0; store.update(copy) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            Button {
                store.remove(snippet)
            } label: {
                Image(systemName: "trash").font(.system(size: 11)).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.mutedForeground)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(Theme.Space.md)
        .background(Theme.muted.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}
