import Foundation
import WhisperKit

/// Progress while fetching a model, so the UI can show something better than a
/// spinner during a 1.5 GB download.
struct ModelLoadProgress: Equatable {
    var fraction: Double
    var detail: String
    var stage: Stage

    enum Stage: Equatable {
        case downloading
        case loading
        case warming
    }
}

/// Wraps WhisperKit. An actor so the model is loaded once and shared safely across
/// dictations. Reloading per utterance would cost seconds every time.
actor Transcriber {

    private var kit: WhisperKit?
    private var loadedModel: String?

    var isLoaded: Bool { kit != nil }

    /// Fetches the model (cached after the first time), then loads and warms it.
    ///
    /// The download is done separately from `WhisperKit.init` rather than letting the
    /// initializer handle it, because only the standalone `download` call reports
    /// progress, and a silent 1.5 GB download looks like the app has hung.
    func load(
        model: String,
        onProgress: (@Sendable (ModelLoadProgress) -> Void)? = nil
    ) async throws {
        if loadedModel == model, kit != nil { return }

        onProgress?(ModelLoadProgress(fraction: 0, detail: "Contacting model host…", stage: .downloading))

        let folder = try await WhisperKit.download(
            variant: model,
            progressCallback: { progress in
                onProgress?(
                    ModelLoadProgress(
                        fraction: progress.fractionCompleted,
                        detail: progress.localizedAdditionalDescription ?? "",
                        stage: .downloading
                    )
                )
            }
        )

        onProgress?(ModelLoadProgress(fraction: 1, detail: "Loading into memory…", stage: .loading))

        let config = WhisperKitConfig(
            model: model,
            modelFolder: folder.path,
            prewarm: true,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
        loadedModel = model

        onProgress?(ModelLoadProgress(fraction: 1, detail: "Ready", stage: .warming))
    }

    func unload() {
        kit = nil
        loadedModel = nil
    }

    /// - Parameter onPartial: fired as decoding progresses, so the overlay can show
    ///   text appearing instead of a spinner.
    func transcribe(
        samples: [Float],
        model: String,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await load(model: model)
        guard let kit else { return "" }

        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { progress in
                onPartial?(progress.text)
                return true // keep going
            }
        )

        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
