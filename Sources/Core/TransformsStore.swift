import Foundation

struct Transform: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var icon: String
    var prompt: String
}

/// Reusable instructions you can run over text, either on the current selection from
/// the main window, or by name in command mode ("run make it formal").
final class TransformsStore: ObservableObject {
    static let shared = TransformsStore()

    private let fileName = "transforms.json"

    @Published private(set) var transforms: [Transform] = [] {
        didSet { DataFile.save(transforms, to: fileName) }
    }

    private init() {
        if let saved = DataFile.load([Transform].self, from: fileName), !saved.isEmpty {
            transforms = saved
        } else {
            transforms = Self.defaults
        }
    }

    func add(name: String, icon: String, prompt: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanPrompt.isEmpty else { return }
        transforms.append(Transform(name: cleanName, icon: icon, prompt: cleanPrompt))
    }

    func update(_ transform: Transform) {
        guard let index = transforms.firstIndex(where: { $0.id == transform.id }) else { return }
        transforms[index] = transform
    }

    func remove(_ transform: Transform) {
        transforms.removeAll { $0.id == transform.id }
    }

    func restoreDefaults() {
        transforms = Self.defaults
    }

    /// Loose name match so "make it shorter" finds the "Shorten" transform.
    func matching(_ spoken: String) -> Transform? {
        let needle = spoken.lowercased()
        return transforms.first { needle.contains($0.name.lowercased()) }
    }

    static let defaults: [Transform] = [
        Transform(name: "Shorten", icon: "arrow.down.right.and.arrow.up.left",
                  prompt: "Make this significantly shorter while keeping every important point. Same voice, same meaning."),
        Transform(name: "Formal", icon: "briefcase",
                  prompt: "Rewrite this in a professional register. No slang or contractions, but don't make it stiff or corporate."),
        Transform(name: "Friendly", icon: "hand.wave",
                  prompt: "Rewrite this to sound warm and conversational, like a message to a colleague you like."),
        Transform(name: "Bullets", icon: "list.bullet",
                  prompt: "Turn this into a tight bulleted list. One idea per bullet, no filler."),
        Transform(name: "Fix grammar", icon: "checkmark.circle",
                  prompt: "Fix grammar, spelling and punctuation only. Change nothing else about the wording."),
        Transform(name: "Summarize", icon: "text.alignleft",
                  prompt: "Summarize this in two or three sentences, capturing the decisions and takeaways.")
    ]
}
