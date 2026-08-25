import Foundation

/// A single always-there text surface. Dictation aimed at the Scratchpad appends
/// here instead of being pasted into another app, which is handy when you want to
/// think out loud without a document open.
final class ScratchpadStore: ObservableObject {
    static let shared = ScratchpadStore()

    private let fileName = "scratchpad.json"

    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            DataFile.save(text, to: fileName)
        }
    }

    private init() {
        text = DataFile.load(String.self, from: fileName) ?? ""
    }

    func append(_ addition: String) {
        let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text += text.isEmpty ? trimmed : "\n\n" + trimmed
    }

    var wordCount: Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}
