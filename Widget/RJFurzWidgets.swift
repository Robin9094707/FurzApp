import WidgetKit
import SwiftUI
import AppIntents

private struct FartWidgetEntry: TimelineEntry {
    let date: Date
    let count: Int
    let score: Int
    let slogan: String
    let period: RJFurzShared.Period
    let updatedAt: Date?
}

private struct FartWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FartWidgetEntry {
        FartWidgetEntry(
            date: .now,
            count: 7,
            score: 420,
            slogan: "Windpark RJ ist online.",
            period: .sevenDays,
            updatedAt: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FartWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FartWidgetEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
    }

    private func makeEntry() -> FartWidgetEntry {
        let period = RJFurzShared.defaultPeriod
        let count = RJFurzShared.count(for: period)
        let score = RJFurzShared.score
        return FartWidgetEntry(
            date: .now,
            count: count,
            score: score,
            slogan: RJFurzShared.slogan(count: count, score: score),
            period: period,
            updatedAt: RJFurzShared.updatedAt
        )
    }
}

private extension RJFurzShared.Period {
    var widgetTitle: String {
        switch self {
        case .day: "24 h"
        case .sevenDays: "7 Tage"
        case .thirtyDays: "30 Tage"
        case .currentWeek: "Diese Woche"
        case .all: "Gesamt"
        }
    }
}

private struct FartCounterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FartWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 9) {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.title2.bold())
                    .foregroundStyle(.tint)
                Text("RJ Furz")
                    .font(.headline)
                Spacer()
                Link(destination: RJFurzShared.quickRecordURL) {
                    Image(systemName: "mic.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Sofort Furzaufnahme starten")
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(entry.count)")
                    .font(.system(size: family == .systemSmall ? 42 : 50, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Fürze")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(entry.period.widgetTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if family != .systemSmall {
                    Label("\(entry.score)", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.slogan)
                .font(family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(family == .systemLarge ? 3 : 2)

            if family == .systemLarge {
                Divider()
                HStack {
                    Label("Antippen öffnet die Notfall-Aufnahme", systemImage: "mic.fill")
                    Spacer()
                    if let updatedAt = entry.updatedAt {
                        Text(updatedAt, style: .relative)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.purple.opacity(0.28), Color.orange.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(RJFurzShared.quickRecordURL)
    }
}

private struct FartCounterWidget: Widget {
    let kind = "eu.rjuhas.furzapp.counter.v2"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FartWidgetProvider()) { entry in
            FartCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("RJ Furzzähler")
        .description("Zeigt deinen Furzzähler und öffnet mit einem Tipp sofort die Aufnahme.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct QuickFartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "eu.rjuhas.furzapp.quickrecord.v2") {
            ControlWidgetButton(action: QuickFartRecordIntent()) {
                Label("Notfall-Furz", systemImage: "mic.fill")
            }
        }
        .displayName("Furzaufnahme")
        .description("Öffnet die RJ Furz-App sofort im Recorder.")
    }
}

@main
struct RJFurzWidgetBundle: WidgetBundle {
    var body: some Widget {
        FartCounterWidget()
        QuickFartControl()
    }
}
