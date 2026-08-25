import Foundation
import Combine

/// The on-device speech model. Chosen by the user during onboarding rather than
/// hardcoded, since the download size / accuracy tradeoff is a personal one.
enum WhisperModelChoice: String, CaseIterable, Identifiable {
    case turbo = "large-v3-v20240930_turbo"
    case smallEn = "small.en"
    case baseEn = "base.en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turbo: return "Large v3 Turbo"
        case .smallEn: return "Small (English)"
        case .baseEn: return "Base (English)"
        }
    }

    var size: String {
        switch self {
        case .turbo: return "~1.5 GB"
        case .smallEn: return "~500 MB"
        case .baseEn: return "~150 MB"
        }
    }

    var blurb: String {
        switch self {
        case .turbo:
            return "Best accuracy and still fast on Apple Silicon. Recommended."
        case .smallEn:
            return "Lighter on disk, quick to download. Slips on names and fast speech."
        case .baseEn:
            return "Smallest and fastest. Noticeably rougher, good for older Macs."
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: - Speech

    @Published var modelChoice: WhisperModelChoice {
        didSet { defaults.set(modelChoice.rawValue, forKey: Keys.model) }
    }

    // MARK: - Triggers

    @Published var dictationKey: TriggerKey {
        didSet { defaults.set(dictationKey.rawValue, forKey: Keys.dictationKey) }
    }
    @Published var commandKey: TriggerKey {
        didSet { defaults.set(commandKey.rawValue, forKey: Keys.commandKey) }
    }

    // MARK: - Cleanup

    @Published var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanup) }
    }
    @Published var appAwareTone: Bool {
        didSet { defaults.set(appAwareTone, forKey: Keys.tone) }
    }
    @Published var groqModel: String {
        didSet { defaults.set(groqModel, forKey: Keys.groqModel) }
    }

    // MARK: - Behaviour

    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.sounds) }
    }
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.hud) }
    }
    @Published var preferDirectWrite: Bool {
        didSet { defaults.set(preferDirectWrite, forKey: Keys.directWrite) }
    }
    @Published var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) }
    }

    private enum Keys {
        static let model = "whisperModel"
        static let dictationKey = "dictationTriggerKey"
        static let commandKey = "commandTriggerKey"
        static let cleanup = "cleanupEnabled"
        static let tone = "appAwareTone"
        static let groqModel = "groqModel"
        static let sounds = "playSounds"
        static let hud = "showHUD"
        static let directWrite = "preferDirectWrite"
        static let onboarded = "hasOnboarded"
    }

    private init() {
        modelChoice = WhisperModelChoice(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .turbo
        dictationKey = TriggerKey(rawValue: defaults.string(forKey: Keys.dictationKey) ?? "") ?? .fn
        commandKey = TriggerKey(rawValue: defaults.string(forKey: Keys.commandKey) ?? "") ?? .off
        cleanupEnabled = defaults.object(forKey: Keys.cleanup) as? Bool ?? true
        appAwareTone = defaults.object(forKey: Keys.tone) as? Bool ?? true
        groqModel = defaults.string(forKey: Keys.groqModel) ?? "llama-3.3-70b-versatile"
        playSounds = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        showHUD = defaults.object(forKey: Keys.hud) as? Bool ?? true
        preferDirectWrite = defaults.object(forKey: Keys.directWrite) as? Bool ?? false
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
    }
}
