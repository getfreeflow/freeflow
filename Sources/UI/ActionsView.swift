import AppKit
import SwiftUI

struct ActionsView: View {
    @ObservedObject private var store = TransformsStore.shared
    @EnvironmentObject private var preferences: Preferences

    @State private var input = ""
    @State private var output = ""
    @State private var running: UUID?
    @State private var showingNew = false
    @State private var name = ""
    @State private var prompt = ""

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: Theme.Space.sm)]

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Actions",
                subtitle: "Saved instructions you can point at any block of text."
            ) {
                Button(showingNew ? "Cancel" : "New action") { showingNew.toggle() }
                    .buttonStyle(ShButtonStyle(variant: showingNew ? .ghost : .primary, size: .sm))
            }

            if showingNew { newForm }

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.sm) {
                ForEach(store.transforms) { transform in
                    ActionCard(
                        transform: transform,
                        running: running == transform.id,
                        run: { run(transform) }
                    )
                }
            }

            workbench

            Text("Once you've set a command key, you can skip this page entirely. Highlight text in any app, hold the key, and say the action's name.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
    }

    private var newForm: some View {
        ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        ShSectionLabel(text: "Name")
                        TextField("Make it a tweet", text: $name)
                            .textFieldStyle(ShTextFieldStyle())
                    }
                    .frame(width: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        ShSectionLabel(text: "Instruction")
                        TextField("Rewrite this as a single punchy tweet under 280 characters.", text: $prompt, axis: .vertical)
                            .textFieldStyle(ShTextFieldStyle())
                            .lineLimit(1...4)
                    }
                }
                HStack {
                    Spacer()
                    Button("Add action") {
                        store.add(name: name, icon: "wand.and.stars", prompt: prompt)
                        name = ""; prompt = ""; showingNew = false
                    }
                    .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var workbench: some View {
        ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Try one out")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.foreground)

                TextField("Drop some text in here, then click an action above to see what it does.", text: $input, axis: .vertical)
                    .textFieldStyle(ShTextFieldStyle())
                    .lineLimit(3...8)

                if !output.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ShSectionLabel(text: "Result")
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(output, forType: .string)
                            }
                            .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                        }
                        Text(output)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(Theme.Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.muted.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    }
                }
            }
        }
    }

    private func run(_ transform: Transform) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            output = "Add some text in the box below first."
            return
        }
        guard CredentialStore.shared.hasKey else {
            output = "Actions run on a Groq API key. You can add one under Settings › Cleanup."
            return
        }

        running = transform.id
        output = ""
        Task {
            let result = (try? await GroqClient().complete(
                system: transform.prompt + "\n\nReturn only the rewritten text. No preamble, no quotes.",
                user: text,
                model: preferences.groqModel
            )) ?? "Couldn't reach the model. Check your connection and API key."

            await MainActor.run {
                output = result
                running = nil
            }
        }
    }
}

private struct ActionCard: View {
    let transform: Transform
    let running: Bool
    let run: () -> Void

    @ObservedObject private var store = TransformsStore.shared
    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Theme.muted)
                        .frame(width: 32, height: 32)
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: transform.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.foreground)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transform.name)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)
                    Text(transform.prompt)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if hovering {
                    Button {
                        store.remove(transform)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 10)).frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.accent : Theme.muted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
