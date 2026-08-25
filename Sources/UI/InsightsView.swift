import SwiftUI

struct InsightsView: View {
    @ObservedObject private var stats = StatsStore.shared
    @State private var range = 14

    var body: some View {
        PageScroll {
            PageHeader(title: "Insights", subtitle: "How much you've actually been talking.") {
                Picker("", selection: $range) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            HStack(spacing: Theme.Space.md) {
                metric(stats.formattedTotalWords, "Total words", "text.word.spacing")
                metric("\(stats.averageWordsPerMinute)", "Average wpm", "gauge.medium")
                metric("\(stats.currentStreak)", "Day streak", "flame")
                metric(stats.timeSavedDescription, "Time saved", "clock.arrow.circlepath")
            }

            chart

            if !stats.topApps.isEmpty {
                topApps
            }
        }
    }

    private func metric(_ value: String, _ label: String, _ icon: String) -> some View {
        ShCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.mutedForeground)
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        let days = stats.recentDays(range)
        let peak = max(days.map(\.words).max() ?? 0, 1)

        return ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack {
                    Text("Words per day")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)
                    Spacer()
                    Text("peak \(peak)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }

                if days.allSatisfy({ $0.words == 0 }) {
                    EmptyState(
                        icon: "chart.bar",
                        title: "No data yet",
                        message: "Dictate something and your daily totals show up here."
                    )
                } else {
                    HStack(alignment: .bottom, spacing: range > 20 ? 3 : 6) {
                        ForEach(days) { day in
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.muted)
                                        .frame(height: 130)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(day.words > 0 ? Theme.primary : Color.clear)
                                        .frame(height: max(2, 130 * CGFloat(day.words) / CGFloat(peak)))
                                }
                                Text(dayLabel(day.day))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                            .help("\(day.words) words · \(day.dictations) dictations")
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = range > 20 ? "d" : "EEEEE"
        return formatter.string(from: date)
    }

    // MARK: - Top apps

    private var topApps: some View {
        let apps = stats.topApps
        let peak = max(apps.first?.words ?? 1, 1)

        return ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Where you dictate")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.foreground)

                ForEach(apps, id: \.name) { app in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(app.name)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.foreground)
                            Spacer()
                            Text("\(app.words)")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.mutedForeground)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.muted)
                                Capsule()
                                    .fill(Theme.primary)
                                    .frame(width: geometry.size.width * CGFloat(app.words) / CGFloat(peak))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }
}
