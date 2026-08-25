import Foundation

struct Meeting: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var duration: TimeInterval
    var transcript: String
    var summary: String

    var durationDescription: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    var wordCount: Int {
        transcript.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}

final class MeetingsStore: ObservableObject {
    static let shared = MeetingsStore()

    private let fileName = "meetings.json"

    @Published private(set) var meetings: [Meeting] = [] {
        didSet { DataFile.save(meetings, to: fileName) }
    }

    private init() {
        meetings = DataFile.load([Meeting].self, from: fileName) ?? []
    }

    func add(_ meeting: Meeting) {
        meetings.insert(meeting, at: 0)
    }

    func update(_ meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[index] = meeting
    }

    func remove(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
    }

    func search(_ query: String) -> [Meeting] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.transcript.localizedCaseInsensitiveContains(trimmed)
                || $0.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
