import AppKit
import SwiftUI

struct StyleView: View {
    @ObservedObject private var store = StyleStore.shared
    @EnvironmentObject private var preferences: Preferences

    @State private var showingNew = false
    @State private var name = ""
    @State private var apps = ""
    @State private var instruction = ""

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Style",
                subtitle: "How FreeFlow writes in each app."
            ) {
                Button(showingNew ? "Cancel" : "New style") { showingNew.toggle() }
                    .buttonStyle(ShButtonStyle(variant: showingNew ? .ghost : .primary, size: .sm))
            }

            if !preferences.appAwareTone {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text("App-aware tone is switched off, so these rules are being ignored. Turn it back on in Settings › Cleanup.")
                        .font(Theme.Typography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.warning)
                .padding(Theme.Space.sm)
                .background(Theme.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }

            if showingNew { newStyleForm }

            VStack(spacing: Theme.Space.sm) {
                ForEach(store.rules) { rule in
                    StyleRuleCard(rule: rule)
                }
            }

            HStack {
                Spacer()
                Button("Restore default styles") { store.restoreDefaults() }
                    .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
            }
        }
    }

    private var newStyleForm: some View {
        ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("New style")
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.foreground)

                HStack(spacing: Theme.Space.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        ShSectionLabel(text: "Name")
                        TextField("Support replies", text: $name)
                            .textFieldStyle(ShTextFieldStyle())
                    }
                    .frame(width: 180)

                    VStack(alignment: .leading, spacing: 4) {
                        ShSectionLabel(text: "App bundle IDs (comma separated)")
                        TextField("com.intercom.app, com.zendesk", text: $apps)
                            .textFieldStyle(ShTextFieldStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ShSectionLabel(text: "Instruction")
                    TextField("Warm but efficient. Lead with the answer.", text: $instruction, axis: .vertical)
                        .textFieldStyle(ShTextFieldStyle())
                        .lineLimit(2...4)
                }

                HStack {
                    Button("Find bundle ID of frontmost app") {
                        apps = AppContext.frontmost().bundleID
                    }
                    .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                    Spacer()
                    Button("Add style") {
                        store.add(
                            name: name,
                            bundleIDs: apps.split(separator: ",").map {
                                $0.trimmingCharacters(in: .whitespaces)
                            },
                            instruction: instruction
                        )
                        name = ""; apps = ""; instruction = ""
                        showingNew = false
                    }
                    .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

private struct StyleRuleCard: View {
    let rule: StyleRule
    @ObservedObject private var store = StyleStore.shared
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        ShCard(padding: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Text(rule.name)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)
                    if rule.isBuiltIn {
                        ShBadge(text: "Built in")
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { rule.enabled },
                        set: { var copy = rule; copy.enabled = $0; store.update(copy) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Button {
                        if editing {
                            var copy = rule
                            copy.instruction = draft
                            store.update(copy)
                        } else {
                            draft = rule.instruction
                        }
                        editing.toggle()
                    } label: {
                        Image(systemName: editing ? "checkmark" : "pencil")
                            .font(.system(size: 11)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.mutedForeground)

                    if !rule.isBuiltIn {
                        Button {
                            store.remove(rule)
                        } label: {
                            Image(systemName: "trash").font(.system(size: 11)).frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.mutedForeground)
                    }
                }

                if editing {
                    TextField("Instruction", text: $draft, axis: .vertical)
                        .textFieldStyle(ShTextFieldStyle())
                        .lineLimit(2...5)
                } else {
                    Text(rule.instruction)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !rule.bundleIDs.isEmpty {
                    Text(rule.bundleIDs.joined(separator: " · "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground.opacity(0.75))
                        .lineLimit(2)
                }
            }
            .opacity(rule.enabled ? 1 : 0.5)
        }
    }
}
