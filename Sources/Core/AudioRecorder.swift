import AVFoundation
import CoreAudio

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
///
/// Safe to call from any thread, hence `@unchecked Sendable`: every piece of shared
/// state is behind `lock` or `controlLock`. Starting can block for most of a second
/// when the input is Bluetooth, so callers on the main thread should hop off it first.
final class AudioRecorder: @unchecked Sendable {

    /// Emitted on the main queue, throttled to roughly 20 fps for the level meter.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Guards `samples` and `converter`, which the audio thread touches.
    private let lock = NSLock()
    /// Serialises start, stop and recovery against each other.
    private let controlLock = NSLock()

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var lastLevelEmit = Date.distantPast
    private var prefersBuiltInMic = false
    private var configurationObserver: NSObjectProtocol?

    private(set) var isRecording = false

    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / targetFormat.sampleRate
    }

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.recoverFromConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    /// - Parameter preferBuiltInMic: record from the Mac's own microphone even when
    ///   something else (usually Bluetooth headphones) is the system input.
    func start(preferBuiltInMic: Bool = false) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard !isRecording else { return }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        prefersBuiltInMic = preferBuiltInMic
        do {
            try startEngine(builtIn: preferBuiltInMic)
        } catch where preferBuiltInMic {
            NSLog("FreeFlow: built-in mic failed (%@), using the system input", String(describing: error))
            try startEngine(builtIn: false)
        }
        isRecording = true
    }

    /// Stops capture and returns everything recorded, clearing the buffer.
    @discardableResult
    func stop() -> [Float] {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard isRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        converter = nil
        lock.unlock()

        return captured
    }

    // MARK: - Engine

    private func startEngine(builtIn: Bool) throws {
        let input = engine.inputNode
        selectDevice(builtIn: builtIn, for: input)

        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw RecorderError.conversionUnavailable
        }

        lock.lock()
        self.converter = converter
        lock.unlock()
        inputFormat = format

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// A device change stops the engine without telling anyone: headphones
    /// connecting, Bluetooth switching into its call profile, the default input
    /// changing. Capture used to end right there, mid-take, and everything said
    /// after it was lost. Samples already captured are kept.
    private func recoverFromConfigurationChange() {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard isRecording else { return }

        // Selecting a device during start can post this too. Nothing to do if the
        // engine came through it running on the format we set up for.
        if engine.isRunning, engine.inputNode.inputFormat(forBus: 0) == inputFormat { return }

        NSLog("FreeFlow: audio device changed mid-take, restarting capture")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try startEngine(builtIn: prefersBuiltInMic)
        } catch {
            NSLog("FreeFlow: could not restart capture: %@", String(describing: error))
            if prefersBuiltInMic { try? startEngine(builtIn: false) }
        }
    }

    private func selectDevice(builtIn: Bool, for input: AVAudioInputNode) {
        guard let unit = input.audioUnit else { return }
        let wanted = builtIn ? (AudioDevices.builtInInput() ?? AudioDevices.defaultInput()) : AudioDevices.defaultInput()
        guard var device = wanted else { return }

        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let read = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size)
        if read == noErr, current == device { return }

        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            NSLog("FreeFlow: could not select input device %u (status %d)", device, status)
        }
    }

    // MARK: - Capture

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let converter = self.converter
        lock.unlock()
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

// MARK: - Core Audio devices

private enum AudioDevices {

    static func defaultInput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// The Mac's own microphone, if it has one.
    static func builtInInput() -> AudioDeviceID? {
        allDevices().first { transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) }
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }

        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}
