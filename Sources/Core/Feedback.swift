import AppKit

/// Audible cues for the end of a take, so you know it registered without looking
/// at the menu bar.
///
/// There is deliberately no start cue. The overlay appearing already confirms it's
/// listening, and a sound on every key press is noise you hear dozens of times a day.
enum Feedback {
    enum Cue {
        case stop
        case cancel

        var soundName: String {
            switch self {
            case .stop: return "Pop"
            case .cancel: return "Funk"
            }
        }
    }

    static func play(_ cue: Cue, enabled: Bool) {
        guard enabled else { return }
        NSSound(named: NSSound.Name(cue.soundName))?.play()
    }
}
