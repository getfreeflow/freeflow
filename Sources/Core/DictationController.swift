import AppKit
import Combine
import Foundation

/// Owns the whole pipeline and the state the UI renders.
///
///   Dictation:  hold key → record → transcribe (local) → clean up → insert
///   Command:    hold key → record → transcribe → rewrite selection / answer → insert
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum Phase: Equatable {
        case idle
        case preparingModel
        case recording
        case transcribing
        case polishing
        case failed(String)
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var mode: TriggerRole = .dictation
    @Published private(set) var level: Float = 0
    @Published private(set) var partialText = ""
    @Published private(set) var lastText = ""
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var modelReady = false
    @Published private(set) var modelStatus = "Model not loaded"
    @Published private(set) var modelProgress: ModelLoadProgress?
    @Published private(set) var modelError: String?
    @Published private(set) var hotkeyActive = false
    @Published private(set) var isLatched = false
    @Published private(set) var lastOutcome: Outcome = .inserted
    @Published var lastWarning: String?

    /// What happened to the most recent take, so the overlay can say so.
    enum Outcome: Equatable {
        case inserted
        /// Nothing focused could accept text, so it's on the clipboard.
        case copied
        /// Dismissed with ✕. Kept in History, not inserted.
        case discarded
    }

    // MARK: - Collaborators

    private let hotkey = HotkeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let groq = GroqClient()

    private let prefs = Preferences.shared
    private let vocabulary = VocabularyStore.shared
    private let snippets = SnippetsStore.shared
    private let history = HistoryStore.shared
    private let stats = StatsStore.shared

    /// Starting and stopping the mic happen here. With Bluetooth input a start can
    /// take most of a second, and on the main thread that froze everything else.
    private let audioQueue = DispatchQueue(label: "FreeFlow.audio", qos: .userInitiated)

    // MARK: - Session state

    private var recordingStartedAt = Date()
    private var targetApp = FrontmostApp.unknown
    private var capturedSelection: String?
    private var elapsedTimer: Timer?
    private var latchWatchdog: Timer?
    private var secondTapTimer: Timer?
    private var heardSpeech = false
    private var cancellables = Set<AnyCancellable>()

    /// A short press has ended and we're waiting to see if a second one follows.
    private var awaitingSecondTap = false
    /// The key-up of the tap that latched belongs to the gesture, not the take.
    private var ignoreNextRelease = false

    /// A press shorter than this is a tap, not a hold.
    private let tapMaxDuration: TimeInterval = 0.3
    /// How long after a first tap a second one still counts. Taps under 120ms are
    /// only reported on key-up (see HotkeyMonitor), so this covers the whole
    /// second tap, not just the gap before it.
    private let doubleTapWindow: TimeInterval = 0.45

    /// A latched take that has captured no speech at all is abandoned after this
    /// long. Only applies before the first word; once you've started talking the
    /// overlay waits indefinitely, so a pause mid-thought is never cut off.
    private let silentLatchTimeout: TimeInterval = 15

    /// Below this a press was a mis-tap rather than speech.
    private let minimumSamples = 4_000 // 0.25s at 16 kHz

    private init() {
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.level = value
                if value > 0.06 { self.heardSpeech = true }
            }
        }
        // HotkeyMonitor delivers on the main queue. Handled synchronously so a tap's
        // press and release are seen in the order they happened.
        hotkey.onPress = { [weak self] role in
            MainActor.assumeIsolated { self?.triggerDown(role) }
        }
        hotkey.onRelease = { [weak self] role, held in
            MainActor.assumeIsolated { self?.triggerUp(role, heldFor: held) }
        }
        hotkey.onCancel = { [weak self] in
            MainActor.assumeIsolated { self?.cancel() }
        }

        // Keep the tap in sync when the trigger keys are changed in Settings.
        prefs.$dictationKey
            .sink { [weak self] key in self?.hotkey.dictationKey = key }
            .store(in: &cancellables)
        prefs.$commandKey
            .sink { [weak self] key in self?.hotkey.commandKey = key }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        hotkey.dictationKey = prefs.dictationKey
        hotkey.commandKey = prefs.commandKey
        hotkeyActive = hotkey.start()

        if !hotkeyActive {
            lastWarning = "FreeFlow can't watch the keyboard yet. Grant Accessibility and Input Monitoring, then hit Retry."
        }

        NSLog(
            "FreeFlow diagnostics: eventTap:%@ accessibility:%@ inputMonitoring:%@ microphone:%@ trigger:%@ command:%@",
            hotkeyActive ? "OK" : "FAILED",
            Permissions.accessibilityGranted ? "granted" : "DENIED",
            Permissions.inputMonitoringGranted ? "granted" : "DENIED",
            Permissions.microphoneGranted ? "granted" : "DENIED",
            prefs.dictationKey.label,
            prefs.commandKey.label
        )

        guard prefs.hasOnboarded else { return }
        Task { await prepareModel() }
    }

    /// True when everything dictation depends on is actually in place.
    var isOperational: Bool {
        hotkeyActive
            && Permissions.accessibilityGranted
            && Permissions.microphoneGranted
            && prefs.dictationKey != .off
    }

    /// Overlay ✓: stop, transcribe, deliver the text.
    func acceptFromOverlay() {
        guard phase == .recording else { return }
        finish(insert: true)
    }

    /// Overlay ✕: stop and transcribe, but don't put the text anywhere.
    ///
    /// Distinct from `cancel()`, which is what `esc` does; that throws the audio away
    /// without transcribing it. This still runs the pipeline so the take lands in
    /// History, it only declines to insert or copy.
    func discardFromOverlay() {
        guard phase == .recording else { return }
        finish(insert: false)
    }

    func restartHotkey() {
        hotkey.stop()
        hotkey.dictationKey = prefs.dictationKey
        hotkey.commandKey = prefs.commandKey
        hotkeyActive = hotkey.start()
        if hotkeyActive { lastWarning = nil }
    }

    func prepareModel() async {
        guard !modelReady else { return }
        phase = .preparingModel
        modelError = nil
        modelStatus = "Preparing \(prefs.modelChoice.title)…"
        do {
            try await transcriber.load(
                model: prefs.modelChoice.rawValue,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.modelProgress = progress
                        self?.modelStatus = Self.describe(progress, model: Preferences.shared.modelChoice.title)
                    }
                }
            )
            modelReady = true
            modelProgress = nil
            modelStatus = "\(prefs.modelChoice.title) ready"
            phase = .idle
        } catch {
            modelReady = false
            modelProgress = nil
            modelError = error.localizedDescription
            modelStatus = "Model failed to load"
            phase = .failed(error.localizedDescription)
            NSLog("FreeFlow: model load failed: %@", String(describing: error))
        }
    }

    private static func describe(_ progress: ModelLoadProgress, model: String) -> String {
        switch progress.stage {
        case .downloading:
            return "Downloading \(model), \(Int(progress.fraction * 100))%"
        case .loading:
            return "Loading \(model) into memory…"
        case .warming:
            return "\(model) ready"
        }
    }

    func reloadModel() async {
        modelReady = false
        modelProgress = nil
        modelError = nil
        await transcriber.unload()
        await prepareModel()
    }

    // MARK: - Trigger handling
    //
    // Hold to talk; letting go inserts. Double-tap to latch recording on, then one
    // more tap (or ✓) stops it. A single tap on its own does nothing.
    //
    // Recording starts on the first press either way, so a hold loses nothing to
    // waiting and a double tap keeps the audio from its first tap.

    private func triggerDown(_ role: TriggerRole) {
        NSLog("FreeFlow: trigger down (%@)", role == .command ? "command" : "dictation")
        guard prefs.hasOnboarded else { return }

        if phase == .recording {
            if isLatched {
                finish() // a tap while latched ends the take
            } else if awaitingSecondTap, role == mode {
                latch()
            }
            return
        }

        guard phase != .transcribing, phase != .polishing else { return }

        if role == .command, !CredentialStore.shared.hasKey {
            lastWarning = "Command mode needs a Groq API key. Add one in Settings."
            return
        }

        mode = role
        isLatched = false
        beginRecording()
    }

    private func triggerUp(_ role: TriggerRole, heldFor held: TimeInterval) {
        guard phase == .recording, role == mode else { return }

        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        guard !isLatched else { return }

        if held < tapMaxDuration {
            // Maybe the first half of a double tap. Keep recording and give up if
            // no second tap arrives.
            awaitingSecondTap = true
            secondTapTimer?.invalidate()
            secondTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.awaitingSecondTap else { return }
                    self.awaitingSecondTap = false
                    self.discardTake(playSound: false) // a stray single tap
                }
            }
        } else {
            finish()
        }
    }

    private func latch() {
        cancelSecondTapWait()
        isLatched = true
        ignoreNextRelease = true
        startLatchWatchdog()
    }

    private func cancelSecondTapWait() {
        awaitingSecondTap = false
        secondTapTimer?.invalidate()
        secondTapTimer = nil
    }

    /// Abandons a latched take that never heard anything, which is what an accidental
    /// double tap looks like. Without it the overlay would sit there indefinitely.
    private func startLatchWatchdog() {
        latchWatchdog?.invalidate()
        latchWatchdog = Timer.scheduledTimer(
            withTimeInterval: silentLatchTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording, self.isLatched else { return }
                guard !self.heardSpeech else { return }
                NSLog("FreeFlow: latched take abandoned, no speech in %.0fs", self.silentLatchTimeout)
                self.cancel()
            }
        }
    }

    private func stopLatchWatchdog() {
        latchWatchdog?.invalidate()
        latchWatchdog = nil
    }

    private func beginRecording() {
        // Checked up front rather than letting the audio engine start and quietly
        // deliver silence. A failed dictation with no explanation is the worst
        // outcome here.
        guard Permissions.microphoneGranted else {
            let message = "Microphone access is off. Turn FreeFlow on under System Settings › Privacy & Security › Microphone."
            NSLog("FreeFlow: recording blocked, microphone permission denied")
            lastWarning = message
            phase = .failed(message)
            showHUD()
            scheduleHUDDismiss(after: 4)
            return
        }

        targetApp = AppContext.frontmost()
        // Grab the selection now, while focus is still where the user left it.
        capturedSelection = mode == .command ? SelectionReader.selectedText() : nil

        // The overlay goes up straight away and the mic starts off the main thread.
        phase = .recording
        partialText = ""
        lastWarning = nil
        heardSpeech = false
        awaitingSecondTap = false
        ignoreNextRelease = false
        recordingStartedAt = Date()
        startElapsedTimer()
        showHUD()

        let preferBuiltIn = prefs.useBuiltInMic
        audioQueue.async { [weak self, recorder] in
            do {
                try recorder.start(preferBuiltInMic: preferBuiltIn)
            } catch {
                Task { @MainActor in self?.recordingFailed(error) }
            }
        }
    }

    private func recordingFailed(_ error: Error) {
        NSLog("FreeFlow: recording failed to start: %@", String(describing: error))
        guard phase == .recording else { return }
        resetTakeState()
        lastWarning = error.localizedDescription
        phase = .failed(error.localizedDescription)
        showHUD() // otherwise the failure is completely invisible
        scheduleHUDDismiss(after: 4)
    }

    private func finish(insert: Bool = true) {
        resetTakeState()
        // Out of .recording now, so presses while the mic shuts down are ignored.
        phase = .transcribing
        Feedback.play(insert ? .stop : .cancel, enabled: prefs.playSounds)

        audioQueue.async { [weak self, recorder] in
            let samples = recorder.stop()
            Task { @MainActor in self?.captured(samples, insert: insert) }
        }
    }

    private func captured(_ samples: [Float], insert: Bool) {
        // Too short, or nothing ever rose above the noise floor. Whisper handed
        // silence doesn't return nothing, it invents a word ("you", "uh"), which is
        // where the stray one-word insertions came from.
        guard samples.count >= minimumSamples, heardSpeech else {
            phase = .idle
            HUDController.shared.hide()
            return
        }
        Task { await process(samples, insert: insert) }
    }

    /// `esc`, or a latched take that heard nothing.
    func cancel() {
        discardTake(playSound: true)
    }

    private func discardTake(playSound: Bool) {
        guard phase == .recording else { return }
        resetTakeState()
        phase = .idle
        HUDController.shared.hide()
        audioQueue.async { [recorder] in _ = recorder.stop() }
        if playSound { Feedback.play(.cancel, enabled: prefs.playSounds) }
    }

    private func resetTakeState() {
        stopElapsedTimer()
        stopLatchWatchdog()
        cancelSecondTapWait()
        isLatched = false
        ignoreNextRelease = false
        level = 0
    }

    // MARK: - Pipeline

    private func process(_ samples: [Float], insert: Bool = true) async {
        phase = .transcribing
        let duration = Double(samples.count) / 16_000

        do {
            let raw = try await transcriber.transcribe(
                samples: samples,
                model: prefs.modelChoice.rawValue,
                onPartial: { [weak self] text in
                    Task { @MainActor in self?.partialText = text.trimmingCharacters(in: .whitespaces) }
                }
            )

            guard !Self.isSilenceArtifact(raw) else {
                phase = .idle
                HUDController.shared.hide()
                return
            }

            var text = snippets.expand(vocabulary.applyCorrections(to: raw))
            guard !text.isEmpty else {
                phase = .idle
                HUDController.shared.hide()
                return
            }

            switch mode {
            case .dictation:
                text = await cleanUp(text)
            case .command:
                guard let result = await runCommand(instruction: text) else {
                    phase = .idle
                    scheduleHUDDismiss()
                    return
                }
                text = result
            }

            lastText = text
            partialText = ""
            // Recorded either way. Declining to insert shouldn't lose the take.
            history.add(text: text, appName: targetApp.name)

            guard insert else {
                // Not counted in stats: those measure text you actually used, and
                // inflating "time saved" with discarded takes would make them a lie.
                lastOutcome = .discarded
                phase = .idle
                scheduleHUDDismiss(after: 1.4)
                return
            }

            stats.record(text: text, duration: duration, appName: targetApp.name)
            let result = TextInjector.inject(text, preferDirectWrite: prefs.preferDirectWrite)
            lastOutcome = result == .copiedToClipboard ? .copied : .inserted
            phase = .idle
            scheduleHUDDismiss(after: result == .copiedToClipboard ? 1.8 : 0.9)
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleHUDDismiss(after: 2.5)
        }
    }

    /// What Whisper produces from breath, room noise or a clipped syllable. Only
    /// dropped when it's the entire transcript, so real words are never touched.
    private static let silenceArtifacts: Set<String> = [
        "uh", "um", "umm", "hmm", "mm", "mhm", "you",
        "blankaudio", "silence", "inaudible", "music"
    ]

    static func isSilenceArtifact(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { silenceArtifacts.contains(String($0)) }
    }

    private func cleanUp(_ text: String) async -> String {
        guard prefs.cleanupEnabled, CredentialStore.shared.hasKey else { return text }
        phase = .polishing

        let system = PromptBuilder.cleanupSystemPrompt(
            app: targetApp,
            appAware: prefs.appAwareTone,
            vocabulary: vocabulary.terms
        )
        do {
            return try await groq.complete(system: system, user: text, model: prefs.groqModel)
        } catch {
            // Never lose a dictation to a cleanup failure. Keep the raw transcript
            // and say why it wasn't polished.
            lastWarning = error.localizedDescription
            return text
        }
    }

    /// Command mode: rewrite the selection if there was one, otherwise answer the
    /// question and insert the answer.
    private func runCommand(instruction: String) async -> String? {
        phase = .polishing

        let system: String
        let user: String

        if let selection = capturedSelection, !selection.isEmpty {
            system = PromptBuilder.rewriteSystemPrompt(vocabulary: vocabulary.terms)
            user = "Instruction: \(instruction)\n\nSelected text:\n\(selection)"
        } else {
            system = PromptBuilder.askSystemPrompt(app: targetApp, vocabulary: vocabulary.terms)
            user = instruction
        }

        do {
            return try await groq.complete(system: system, user: user, model: prefs.groqModel)
        } catch {
            lastWarning = error.localizedDescription
            return nil
        }
    }

    // MARK: - HUD

    private func showHUD() {
        guard prefs.showHUD else { return }
        HUDController.shared.show(controller: self)
    }

    private func scheduleHUDDismiss(after seconds: TimeInterval = 0.9) {
        guard prefs.showHUD else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.phase != .recording else { return }
            HUDController.shared.hide()
        }
    }

    // MARK: - Elapsed timer

    private func startElapsedTimer() {
        elapsed = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.recordingStartedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Derived UI state

    var triggerLabel: String {
        (mode == .command ? prefs.commandKey : prefs.dictationKey).label
    }

    var elapsedDescription: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var statusText: String {
        switch phase {
        case .idle:
            return modelReady ? "Ready. Hold \(prefs.dictationKey.label) to talk" : modelStatus
        case .preparingModel:
            return modelStatus
        case .recording:
            return isLatched ? "Listening. Tap \(triggerLabel) to stop" : "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .polishing:
            return mode == .command ? "Thinking…" : "Cleaning up…"
        case .failed(let message):
            return message
        }
    }

    var isBusy: Bool {
        phase == .transcribing || phase == .polishing || phase == .preparingModel
    }
}
