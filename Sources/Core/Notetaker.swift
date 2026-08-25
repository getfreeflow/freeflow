import AVFoundation
import Foundation
import ScreenCaptureKit

enum NotetakerError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display available to capture audio from."
        case .permissionDenied:
            return "FreeFlow needs Screen Recording access to hear meeting audio. Grant it in System Settings › Privacy & Security › Screen Recording, then reopen FreeFlow."
        }
    }
}

// MARK: - System audio

/// Captures what the *other people* on the call are saying, straight from the system
/// audio mix. No bot joins the meeting, and it works with Zoom, Meet, Teams, Slack
/// huddles or anything else that makes sound.
///
/// ScreenCaptureKit is the only supported way to read system audio on modern macOS.
/// We ask for a 2×2 video stream because a content filter is mandatory, then ignore
/// the video entirely.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {

    private var stream: SCStream?
    private var samples: [Float] = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.freeflow.systemaudio")
    private var converter: AVAudioConverter?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw NotetakerError.permissionDenied
        }
        guard let display = content.displays.first else { throw NotetakerError.noDisplay }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // The video side is mandatory but useless to us, so keep it cheap.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async -> [Float] {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        converter = nil

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return captured
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let chunk = floats(from: sampleBuffer), !chunk.isEmpty else { return }
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    // MARK: Conversion

    private func floats(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let description = sampleBuffer.formatDescription,
              var asbd = description.audioStreamBasicDescription,
              let inputFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        return try? sampleBuffer.withAudioBufferList { list, _ in
            guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: list.unsafePointer) else {
                return [Float]()
            }
            return resample(input, from: inputFormat)
        }
    }

    private func resample(_ buffer: AVAudioPCMBuffer, from format: AVAudioFormat) -> [Float] {
        if converter == nil || converter?.inputFormat != format {
            converter = AVAudioConverter(from: format, to: targetFormat)
        }
        guard let converter else { return [] }

        let ratio = targetFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return [] }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, let channel = output.floatChannelData, output.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}

// MARK: - Recorder

/// Records a meeting: their audio via ScreenCaptureKit, your voice via the mic, mixed
/// into one track, transcribed on-device, then summarized.
@MainActor
final class MeetingRecorder: ObservableObject {
    static let shared = MeetingRecorder()

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case summarizing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0

    private let systemAudio = SystemAudioCapture()
    private let mic = AudioRecorder()
    private let transcriber = Transcriber()
    private let groq = GroqClient()

    private var startedAt = Date()
    private var timer: Timer?

    private init() {
        mic.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
    }

    var isRecording: Bool { state == .recording }

    var elapsedDescription: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func start() async {
        guard state == .idle || isFailed else { return }
        do {
            try await systemAudio.start()
            try? mic.start() // a meeting without your side is still worth capturing
            startedAt = Date()
            elapsed = 0
            state = .recording
            startTimer()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .recording else { return }
        stopTimer()

        let duration = Date().timeIntervalSince(startedAt)
        let theirAudio = await systemAudio.stop()
        let myAudio = mic.stop()
        let mixed = Self.mix(theirAudio, myAudio)

        guard mixed.count > 16_000 else { // under a second of audio
            state = .idle
            return
        }

        state = .transcribing
        do {
            let transcript = try await transcriber.transcribe(
                samples: mixed,
                model: Preferences.shared.modelChoice.rawValue
            )
            guard !transcript.isEmpty else {
                state = .idle
                return
            }

            var summary = ""
            var title = Self.fallbackTitle()

            if CredentialStore.shared.hasKey {
                state = .summarizing
                summary = (try? await groq.complete(
                    system: Self.summaryPrompt,
                    user: transcript,
                    model: Preferences.shared.groqModel
                )) ?? ""

                if let generated = try? await groq.complete(
                    system: "Give this meeting transcript a short title of at most six words. Output only the title, no quotes.",
                    user: String(transcript.prefix(4000)),
                    model: Preferences.shared.groqModel
                ), !generated.isEmpty {
                    title = generated
                }
            }

            MeetingsStore.shared.add(
                Meeting(
                    title: title,
                    date: startedAt,
                    duration: duration,
                    transcript: transcript,
                    summary: summary
                )
            )
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Answers a question about a past meeting using its transcript.
    func ask(_ question: String, about meeting: Meeting) async -> String {
        guard CredentialStore.shared.hasKey else {
            return "Add a Groq API key in Settings to ask questions about meetings."
        }
        let system = """
        Answer questions about this meeting transcript. Be direct and specific, and quote \
        the transcript when it helps. If the answer genuinely isn't in the transcript, say so \
        plainly rather than guessing.

        Transcript:
        \(meeting.transcript.prefix(12000))
        """
        return (try? await groq.complete(system: system, user: question, model: Preferences.shared.groqModel))
            ?? "Couldn't reach the model. Check your connection and API key."
    }

    // MARK: - Private

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Sums the two tracks, padding the shorter one. Both are 16 kHz mono and start
    /// within a few milliseconds of each other, so index alignment is close enough
    /// for transcription.
    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        let count = max(a.count, b.count)
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            output[index] = max(-1, min(1, left + right))
        }
        return output
    }

    private static func fallbackTitle() -> String {
        "Meeting on " + Date().formatted(date: .abbreviated, time: .shortened)
    }

    private static let summaryPrompt = """
    Summarize this meeting transcript for someone who missed it.

    Structure it as:
    - A two or three sentence overview
    - **Key points** as bullets, grouped by topic
    - **Decisions** if any were made
    - **Action items** with who owns them, if identifiable

    The transcript comes from automatic speech recognition and has no speaker labels, so \
    infer speakers only when it's genuinely clear from context. Skip any section that has \
    nothing in it. Use markdown. No preamble.
    """

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
