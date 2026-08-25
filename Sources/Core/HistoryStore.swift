import Foundation

struct DictationEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    var text: String
    let appName: String
    var pinned: Bool

    init(text: String, appName: String) {
        self.id = UUID()
        self.date = Date()
        self.text = text
        self.appName = appName
        self.pinned = false
    }
}

/// Clipboard-style history of everything dictated, so a paste that landed in the
/// wrong window isn't lost.
///
/// Stored as JSON in Application Support rather than UserDefaults, because this grows to
/// hundreds of entries, which is more than defaults should be carrying.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let limit = 500

    @Published private(set) var entries: [DictationEntry] = []

    private lazy var fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }()

    private init() {
        load()
    }

    func add(text: String, appName: String) {
        entries.insert(DictationEntry(text: text, appName: appName), at: 0)
        trim()
        persist()
    }

    func togglePin(_ entry: DictationEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        sort()
        persist()
    }

    func remove(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    /// Clears everything except pinned entries.
    func clear() {
        entries.removeAll { !$0.pinned }
        persist()
    }

    func search(_ query: String) -> [DictationEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed)
                || $0.appName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DictationEntry].self, from: data) else { return }
        entries = decoded
        sort()
    }

    private func sort() {
        entries.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.date > rhs.date
        }
    }

    private func trim() {
        guard entries.count > limit else { return }
        var kept = entries.filter(\.pinned)
        let unpinned = entries.filter { !$0.pinned }.prefix(limit - kept.count)
        kept.append(contentsOf: unpinned)
        entries = kept
        sort()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
