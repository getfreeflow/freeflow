import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    @State private var step = 0
    @State private var apiKey = ""
    @State private var micGranted = Permissions.microphoneGranted
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let permissionPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let stepCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            progress

            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: triggerStep
                    case 2: modelStep
                    case 3: permissionsStep
                    default: apiKeyStep
                    }
                }
                .padding(.bottom, Theme.Space.sm)
            }

            controls
        }
        .padding(Theme.Space.lg)
        .frame(minHeight: 440)
        .onReceive(permissionPoll) { _ in
            micGranted = Permissions.microphoneGranted
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.primary : Theme.border)
                    .frame(height: 3)
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.foreground)

            Text("Welcome to FreeFlow")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)

            Text("Say what you mean and it lands where your cursor already is. Everything you speak is transcribed here on your Mac. No audio leaves the machine unless you switch on cleanup.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            ShCard(padding: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Hold to talk, release to insert", systemImage: "mic")
                    Label("Tap to lock recording on", systemImage: "lock")
                    Label("Press esc to cancel", systemImage: "escape")
                }
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Pick your keys")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ShSectionLabel(text: "Dictation")
                Picker("", selection: $preferences.dictationKey) {
                    ForEach(TriggerKey.allCases.filter { $0 != .off }) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ShSectionLabel(text: "Command mode (optional)")
                Picker("", selection: $preferences.commandKey) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("Highlight something, hold this key, and say what to change. Needs a Groq key.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }

            if preferences.dictationKey.needsSystemSettingsChange
                || preferences.commandKey.needsSystemSettingsChange {
                ShCard(padding: Theme.Space.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("macOS claims the fn key", systemImage: "keyboard")
                            .font(Theme.Typography.bodyMedium)
                            .foregroundStyle(Theme.foreground)
                        Text("By default fn opens Dictation or Emoji and swallows the press. Set “Press 🌐 key to” to “Do Nothing”.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Keyboard settings") { Permissions.openKeyboardSettings() }
                            .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                    }
                }
            }
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Choose a speech model")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)

            Text("Downloaded once, then cached and run entirely on your Mac. Switchable later in Settings.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(WhisperModelChoice.allCases) { model in
                Button {
                    preferences.modelChoice = model
                } label: {
                    ModelOptionRow(model: model, selected: preferences.modelChoice == model)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Grant access")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)

            permissionRow(
                title: "Microphone",
                subtitle: Permissions.microphoneWasDenied
                    ? "Refused earlier. Enable it in System Settings"
                    : "To hear you",
                granted: micGranted
            ) {
                Permissions.resolveMicrophone { micGranted = $0 }
            }

            permissionRow(title: "Accessibility", subtitle: "To insert text into other apps", granted: accessibilityGranted) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }

            permissionRow(title: "Input Monitoring", subtitle: "To notice your trigger key", granted: controller.hotkeyActive) {
                Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
            }

            Button("Recheck") { controller.restartHotkey() }
                .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))

            Text("macOS may ask you to quit and reopen FreeFlow after granting these.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Theme.success : Theme.mutedForeground)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Typography.bodyMedium)
                    .foregroundStyle(Theme.foreground)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }

            Spacer(minLength: 0)

            if !granted {
                Button("Grant", action: action)
                    .buttonStyle(ShButtonStyle(variant: .secondary, size: .sm))
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Connect cleanup")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.foreground)

            Text("Raw speech-to-text isn't something you'd send to anyone. A free Groq key is what turns it into finished writing, and it's what commands, actions and meeting summaries run on.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button("Get a free key at console.groq.com") {
                NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
            }
            .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))

            VStack(alignment: .leading, spacing: 6) {
                ShSectionLabel(text: "API key")
                SecureField("gsk_…", text: $apiKey)
                    .textFieldStyle(ShTextFieldStyle())
                Text("Saved to Application Support, readable only by your account. It isn't encrypted, and it never goes near the repository.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("You can skip this. FreeFlow still dictates, it just inserts the raw transcript.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Theme.Space.sm) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(ShButtonStyle(variant: .ghost, size: .md))
            }
            Spacer()
            if step < stepCount - 1 {
                Button("Continue") { step += 1 }
                    .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
            } else {
                Button("Start dictating") { finish() }
                    .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
            }
        }
    }

    private func finish() {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            CredentialStore.shared.save(apiKey)
        }
        preferences.hasOnboarded = true
        controller.restartHotkey()
        Task { await controller.prepareModel() }
    }
}
