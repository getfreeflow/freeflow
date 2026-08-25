import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelSettings()
                .tabItem { Label("Model", systemImage: "waveform") }
            CleanupSettings()
                .tabItem { Label("Cleanup", systemImage: "wand.and.stars") }
            VocabularySettings()
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
        .background(Theme.background)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var controller: DictationController

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        SettingsPage {
            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    ShSettingRow(
                        title: "Dictation key",
                        subtitle: "Hold to talk, or tap to lock recording on"
                    ) {
                        triggerPicker($preferences.dictationKey)
                    }

                    ShSeparator()

                    ShSettingRow(
                        title: "Command key",
                        subtitle: "Speak an instruction to rewrite selected text, or ask a question"
                    ) {
                        triggerPicker($preferences.commandKey)
                    }

                    if preferences.dictationKey.needsSystemSettingsChange
                        || preferences.commandKey.needsSystemSettingsChange {
                        calloutFnKey
                    }

                    if preferences.dictationKey == preferences.commandKey,
                       preferences.dictationKey != .off {
                        Text("Both triggers use the same key, so command mode won't fire.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    ShSettingRow(title: "Launch at login", subtitle: "Start FreeFlow when you log in") {
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                launchError = LaunchAtLogin.set(newValue)
                                launchAtLogin = LaunchAtLogin.isEnabled
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if let launchError {
                        Text(launchError)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ShSeparator()

                    ShSettingRow(title: "Recording overlay", subtitle: "Show a panel near the bottom of the screen while recording") {
                        Toggle("", isOn: $preferences.showHUD)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    ShSeparator()

                    ShSettingRow(title: "Sound feedback", subtitle: "Play a cue when recording starts and stops") {
                        Toggle("", isOn: $preferences.playSounds)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    ShSeparator()

                    ShSettingRow(
                        title: "Insert without the clipboard",
                        subtitle: "Writes directly into the field where supported. Faster, but some apps ignore it. Leave it off if text goes missing."
                    ) {
                        Toggle("", isOn: $preferences.preferDirectWrite)
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
            }

            ShCard {
                ShSettingRow(
                    title: "Keyboard access",
                    subtitle: controller.hotkeyActive
                        ? "FreeFlow is watching for your trigger keys"
                        : "Not active. Grant Accessibility and Input Monitoring"
                ) {
                    if controller.hotkeyActive {
                        ShBadge(text: "Active", tone: .success)
                    } else {
                        Button("Retry") { controller.restartHotkey() }
                            .buttonStyle(ShButtonStyle(variant: .secondary, size: .sm))
                    }
                }
            }
        }
    }

    private func triggerPicker(_ binding: Binding<TriggerKey>) -> some View {
        Picker("", selection: binding) {
            ForEach(TriggerKey.allCases) { key in
                Text(key.label).tag(key)
            }
        }
        .labelsHidden()
        .frame(width: 130)
        .onChange(of: binding.wrappedValue) { _, _ in
            controller.restartHotkey()
        }
    }

    private var calloutFnKey: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("macOS claims the fn key", systemImage: "keyboard")
                .font(Theme.Typography.bodyMedium)
                .foregroundStyle(Theme.foreground)
            Text("By default fn opens Dictation or Emoji, which swallows it before FreeFlow sees it. Set “Press 🌐 key to” to “Do Nothing”.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Keyboard settings") { Permissions.openKeyboardSettings() }
                .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
        }
        .padding(Theme.Space.md)
        .background(Theme.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

// MARK: - Model

private struct ModelSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        SettingsPage {
            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack {
                        Text("Speech model")
                            .font(Theme.Typography.heading)
                            .foregroundStyle(Theme.foreground)
                        Spacer()
                        ShBadge(
                            text: controller.modelReady ? "Ready" : "Not loaded",
                            tone: controller.modelReady ? .success : .neutral
                        )
                    }

                    Text("Runs entirely on your Mac. Audio never leaves the machine. Switching downloads the new model once, then caches it.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(WhisperModelChoice.allCases) { model in
                        Button {
                            guard preferences.modelChoice != model else { return }
                            preferences.modelChoice = model
                            Task { await controller.reloadModel() }
                        } label: {
                            ModelOptionRow(model: model, selected: preferences.modelChoice == model)
                        }
                        .buttonStyle(.plain)
                    }

                    ShSeparator()

                    HStack(spacing: Theme.Space.md) {
                        if let progress = controller.modelProgress {
                            if progress.stage == .downloading {
                                ProgressRing(fraction: progress.fraction, size: 38, lineWidth: 3.5)
                            } else {
                                ProgressView().controlSize(.small).frame(width: 38)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.modelStatus)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.foreground)
                            if let progress = controller.modelProgress, !progress.detail.isEmpty {
                                Text(progress.detail)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                        }

                        Spacer()

                        Button("Reload") { Task { await controller.reloadModel() } }
                            .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                            .disabled(controller.modelProgress != nil)
                    }
                }
            }
        }
    }
}

/// Shared by Settings and onboarding so the model list looks the same in both.
struct ModelOptionRow: View {
    let model: WhisperModelChoice
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Theme.foreground : Theme.mutedForeground)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)
                    ShBadge(text: model.size)
                }
                Text(model.blurb)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(selected ? Theme.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(selected ? Theme.ring : Theme.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Cleanup

private struct CleanupSettings: View {
    @EnvironmentObject private var preferences: Preferences

    @State private var apiKey = ""
    @ObservedObject private var credentials = CredentialStore.shared
    @State private var validating = false
    @State private var validationResult: Bool?

    var body: some View {
        SettingsPage {
            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    ShSettingRow(
                        title: "Clean up transcripts",
                        subtitle: "Remove filler words, fix grammar, format for the app you're in"
                    ) {
                        Toggle("", isOn: $preferences.cleanupEnabled)
                            .labelsHidden().toggleStyle(.switch)
                    }

                    ShSeparator()

                    ShSettingRow(
                        title: "Match the app's tone",
                        subtitle: "Terser in Slack, more formal in Mail, literal in code editors"
                    ) {
                        Toggle("", isOn: $preferences.appAwareTone)
                            .labelsHidden().toggleStyle(.switch)
                            .disabled(!preferences.cleanupEnabled)
                    }
                }
            }

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack {
                        Text("Groq API key")
                            .font(Theme.Typography.heading)
                            .foregroundStyle(Theme.foreground)
                        Spacer()
                        if let savedKey = credentials.masked {
                            Text(savedKey)
                                .font(Theme.Typography.mono)
                                .foregroundStyle(Theme.mutedForeground)
                        } else {
                            ShBadge(text: "Not set", tone: .warning)
                        }
                    }

                    Text("Kept in a file in Application Support that only your account can read. Without a key FreeFlow still dictates, it just inserts the raw transcript, and command mode is unavailable.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("gsk_…", text: $apiKey)
                        .textFieldStyle(ShTextFieldStyle())
                        .onSubmit(save)

                    HStack(spacing: Theme.Space.sm) {
                        Button("Save", action: save)
                            .buttonStyle(ShButtonStyle(variant: .primary, size: .sm))
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Test", action: test)
                            .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                            .disabled(validating || credentials.masked == nil)

                        Button("Remove") {
                            credentials.remove()
                            validationResult = nil
                            validationResult = nil
                        }
                        .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                        .disabled(credentials.masked == nil)

                        Spacer()

                        if validating {
                            ProgressView().controlSize(.small)
                        } else if let validationResult {
                            ShBadge(
                                text: validationResult ? "Key works" : "Key rejected",
                                tone: validationResult ? .success : .danger
                            )
                        }
                    }

                    Button("Get a free key at console.groq.com") {
                        NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
                    }
                    .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                }
            }

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Command mode")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)
                    Text("Hold your command key and speak an instruction. If text is selected it gets rewritten in place; if nothing is selected, your question is answered and the answer inserted at the cursor.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("“Make this shorter and less formal”", systemImage: "text.quote")
                        Label("“Turn these into bullet points”", systemImage: "list.bullet")
                        Label("“What's the git command to undo a commit?”", systemImage: "questionmark.circle")
                    }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func save() {
        credentials.save(apiKey)

        apiKey = ""
        validationResult = nil
    }

    private func test() {
        validating = true
        validationResult = nil
        Task {
            let ok = await GroqClient().validateKey()
            await MainActor.run {
                validationResult = ok
                validating = false
            }
        }
    }
}

// MARK: - Vocabulary

private struct VocabularySettings: View {
    @ObservedObject private var vocabulary = VocabularyStore.shared
    @State private var newTerm = ""

    var body: some View {
        SettingsPage {
            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Custom vocabulary")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)

                    Text("Names, products and jargon that keep getting misheard. These are handed to the cleanup model so it spells them your way.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Space.sm) {
                        TextField("Add a word or phrase", text: $newTerm)
                            .textFieldStyle(ShTextFieldStyle())
                            .onSubmit(add)
                        Button("Add", action: add)
                            .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
                            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if vocabulary.terms.isEmpty {
                        Text("Nothing added yet.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.vertical, Theme.Space.sm)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(vocabulary.terms, id: \.self) { term in
                                    HStack {
                                        Text(term)
                                            .font(Theme.Typography.body)
                                            .foregroundStyle(Theme.foreground)
                                        Spacer()
                                        Button {
                                            vocabulary.remove(term)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10))
                                                .frame(width: 20, height: 20)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.mutedForeground)
                                    }
                                    .padding(.horizontal, Theme.Space.sm)
                                    .padding(.vertical, 5)
                                    .background(Theme.muted.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                }
                            }
                        }
                        .frame(maxHeight: 210)
                    }
                }
            }
        }
    }

    private func add() {
        vocabulary.add(newTerm)
        newTerm = ""
    }
}

// MARK: - About

private struct AboutSettings: View {
    @ObservedObject private var stats = StatsStore.shared

    var body: some View {
        SettingsPage {
            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Your usage")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)

                    HStack(spacing: Theme.Space.xl) {
                        metric("\(stats.totalWords)", "words dictated")
                        metric("\(stats.totalDictations)", "dictations")
                        metric(stats.timeSavedDescription, "saved vs typing")
                    }

                    Text("Time saved compares speaking at about 150 words a minute with typing at about 40.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Reset statistics") { stats.reset() }
                        .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                }
            }

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("FreeFlow")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)
                    Text("Free, open-source voice dictation for macOS. Transcription runs on-device with WhisperKit; cleanup is optional and uses your own Groq key.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Space.sm) {
                        Button("WhisperKit") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                        }
                        .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                        Button("Groq") {
                            NSWorkspace.shared.open(URL(string: "https://groq.com")!)
                        }
                        .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                    }
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
    }
}

// MARK: - Shared page chrome

private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                content
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.background)
    }
}
