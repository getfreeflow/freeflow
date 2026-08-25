import AVFoundation

enum RecorderError: LocalizedError {
    case noInputDevice
    case conversionUnavailable

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available. Check your input device in System Settings › Sound."
        case .conversionUnavailable:
            return "Could not set up audio conversion for the selected microphone."
        }
    }
}

/// Captures the mic and hands back 16 kHz mono Float32, exactly the shape
/// WhisperKit wants, so no intermediate file ever hits disk.
final class AudioRecorder {

    /// Emitted on the main queue, throttled to roughly 20 fps for the level meter.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var lastLevelEmit = Date.distantPast

    private(set) var isRecording = false

    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / targetFormat.sampleRate
    }

    func start() throws {
        guard !isRecording else { return }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.conversionUnavailable
        }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops capture and returns everything recorded, clearing the buffer.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRecording = false

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        return captured
    }

    // MARK: - Private

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              let channel = output.floatChannelData,
              output.frameLength > 0 else { return }

        let frames = Int(output.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: frames))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        emitLevel(for: chunk)
    }

    private func emitLevel(for chunk: [Float]) {
        guard let onLevel, !chunk.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLevelEmit) > 0.05 else { return }
        lastLevelEmit = now

        var sum: Float = 0
        for sample in chunk { sum += sample * sample }
        let rms = (sum / Float(chunk.count)).squareRoot()

        // Map RMS onto a 0...1 curve that actually looks alive on a meter.
        let normalized = min(1, max(0, rms * 12))
        DispatchQueue.main.async { onLevel(normalized) }
    }
}
