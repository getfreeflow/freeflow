import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var enabled = true
}

/// Spoken shorthand that expands into boilerplate. Say "my email" and get the
/// address, say "standup template" and get the whole block.
///
/// Applied after transcription and before cleanup, so the expansion still gets
/// formatted to fit the app you're writing in.
final class SnippetsStore: ObservableObject {
    static let shared = SnippetsStore()

    private let fileName = "snippets.json"

    @Published private(set) var snippets: [Snippet] = [] {
        didSet { DataFile.save(snippets, to: fileName) }
    }

    private init() {
        snippets = DataFile.load([Snippet].self, from: fileName) ?? []
    }

    func add(trigger: String, expansion: String) {
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExpansion = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTrigger.isEmpty, !cleanExpansion.isEmpty else { return }
        snippets.append(Snippet(trigger: cleanTrigger, expansion: cleanExpansion))
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
    }

    func remove(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    /// Replaces any spoken trigger found in the transcript. Longest triggers first so
    /// "my work email" wins over "my email".
    func expand(_ text: String) -> String {
        var output = text
        let active = snippets
            .filter { $0.enabled }
            .sorted { $0.trigger.count > $1.trigger.count }

        for snippet in active {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: snippet.trigger))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: NSRange(output.startIndex..., in: output),
                withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion)
            )
        }
        return output
    }
}
