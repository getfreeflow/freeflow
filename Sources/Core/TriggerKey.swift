import CoreGraphics
import Foundation

/// Which physical modifier starts a recording.
///
/// `fn` is the default because it's the one key nothing else uses, but plenty of
/// people have it bound to Dictation or Emoji and would rather not change that, so
/// the right-hand modifiers are offered as alternatives. Each is identified by the
/// keycode of the *physical* key, which is how we tell right-⌥ from left-⌥.
enum TriggerKey: String, CaseIterable, Identifiable, Codable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
    case rightShift
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .rightControl: return "Right ⌃"
        case .rightShift: return "Right ⇧"
        case .off: return "Off"
        }
    }

    var keyCode: Int64? {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        case .off: return nil
        }
    }

    var flag: CGEventFlags? {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        case .off: return nil
        }
    }

    /// macOS reserves fn for Dictation/Emoji unless the user turns that off.
    var needsSystemSettingsChange: Bool { self == .fn }
}

/// What a trigger is being held for.
enum TriggerRole: Equatable {
    case dictation
    case command
}
