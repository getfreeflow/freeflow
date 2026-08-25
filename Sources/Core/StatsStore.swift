import Foundation

struct DailyStat: Codable, Identifiable, Equatable {
    var day: Date          // start of day
    var words: Int
    var dictations: Int
    var seconds: Double

    var id: Date { day }

    /// Words per minute actually spoken that day.
    var wordsPerMinute: Int {
        guard seconds > 1 else { return 0 }
        return Int((Double(words) / (seconds / 60)).rounded())
    }
}

/// Usage history, bucketed by day so Insights can show trends, streaks and speaking
/// rate rather than just a lifetime counter.
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    private let fileName = "stats.json"

    @Published private(set) var days: [DailyStat] = []
    @Published private(set) var wordsByApp: [String: Int] = [:]

    private struct Payload: Codable {
        var days: [DailyStat]
        var wordsByApp: [String: Int]
    }

    private init() {
        guard let payload = DataFile.load(Payload.self, from: fileName) else { return }
        days = payload.days
        wordsByApp = payload.wordsByApp
    }

    func record(text: String, duration: TimeInterval, appName: String) {
        let words = text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        guard words > 0 else { return }

        let today = Calendar.current.startOfDay(for: Date())
        if let index = days.firstIndex(where: { $0.day == today }) {
            days[index].words += words
            days[index].dictations += 1
            days[index].seconds += duration
        } else {
            days.append(DailyStat(day: today, words: words, dictations: 1, seconds: duration))
        }
        days.sort { $0.day < $1.day }

        if !appName.isEmpty {
            wordsByApp[appName, default: 0] += words
        }
        persist()
    }

    func reset() {
        days.removeAll()
        wordsByApp.removeAll()
        persist()
    }

    private func persist() {
        DataFile.save(Payload(days: days, wordsByApp: wordsByApp), to: fileName)
    }

    // MARK: - Derived

    var totalWords: Int { days.reduce(0) { $0 + $1.words } }
    var totalDictations: Int { days.reduce(0) { $0 + $1.dictations } }
    var totalSeconds: Double { days.reduce(0) { $0 + $1.seconds } }

    var averageWordsPerMinute: Int {
        guard totalSeconds > 1 else { return 0 }
        return Int((Double(totalWords) / (totalSeconds / 60)).rounded())
    }

    /// Consecutive days ending today (or yesterday, so the streak survives until
    /// you've had a chance to dictate today).
    var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activeDays = Set(days.filter { $0.words > 0 }.map(\.day))
        guard !activeDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = today
        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  activeDays.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Last `count` days including today, zero-filled so charts don't have gaps.
    func recentDays(_ count: Int) -> [DailyStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return days.first { $0.day == day }
                ?? DailyStat(day: day, words: 0, dictations: 0, seconds: 0)
        }
    }

    var topApps: [(name: String, words: Int)] {
        wordsByApp.sorted { $0.value > $1.value }.prefix(6).map { (name: $0.key, words: $0.value) }
    }

    // MARK: - Time saved (speaking ~150 wpm vs typing ~40 wpm)

    private static let typingWPM = 40.0
    private static let speakingWPM = 150.0

    var minutesSaved: Double {
        let words = Double(totalWords)
        return max(0, words / Self.typingWPM - words / Self.speakingWPM)
    }

    var timeSavedDescription: String {
        let minutes = minutesSaved
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        return String(format: "%.1f hr", minutes / 60)
    }

    var formattedTotalWords: String {
        totalWords >= 1000
            ? String(format: "%.1fK", Double(totalWords) / 1000)
            : "\(totalWords)"
    }
}
