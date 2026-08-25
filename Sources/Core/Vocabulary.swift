import Foundation

/// Names, jargon and product terms Whisper tends to mangle.
///
/// Used two ways: a deterministic pass that fixes the casing of terms we already
/// know, and as a hint list handed to the cleanup model, which is what actually
/// rescues badly misheard proper nouns.
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    private let key = "vocabularyTerms"

    @Published private(set) var terms: [String] {
        didSet { UserDefaults.standard.set(terms, forKey: key) }
    }

    private init() {
        terms = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        terms.append(trimmed)
    }

    func remove(_ term: String) {
        terms.removeAll { $0 == term }
    }

    func remove(atOffsets offsets: IndexSet) {
        terms.remove(atOffsets: offsets)
    }

    /// Restores the exact spelling/casing the user registered, for terms the
    /// transcript already got phonetically right.
    func applyCorrections(to text: String) -> String {
        var output = text
        for term in terms {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: term)
            )
        }
        return output
    }
}
