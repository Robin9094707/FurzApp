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
        FartWidgetEntry(date: .now, count: 7, score: 420, slogan: "Windpark RJ ist online.", period: .sevenDays, updatedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (FartWidgetEntry) -> Void) { completion(makeEntry()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FartWidgetEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .after(Date().addingTimeInterval(5 * 60))))
    }

    private func makeEntry() -> FartWidgetEntry {
        let period = RJFurzShared.defaultPeriod
        let count = RJFurzShared.count(for: period)
        let score = RJFurzShared.score
        return FartWidgetEntry(date: .now, count: count, score: score,
                               slogan: RJFurzShared.slogan(count: count, score: score),
                               period: period, updatedAt: RJFurzShared.updatedAt)
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
        Group {
            if family == .systemSmall { small }
            else { expanded }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color.purple.opacity(0.30), Color.orange.opacity(0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(RJFurzShared.quickRecordURL)
    }

    private var small: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "wind")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                Text("RJ Furz")
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }

            Spacer(minLength: 0)
            Text("💨")
                .font(.system(size: 31))
                .accessibilityLabel("Furz-Wind")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.count)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                Text("Fürze")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Text(entry.period.widgetTitle)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.slogan)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "wind")
                    .font(.headline.bold())
                    .foregroundStyle(.tint)
                Text("RJ Furz")
                    .font(.headline)
                Spacer()
                Label("Aufnehmen", systemImage: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
            }

            HStack(spacing: 12) {
                Text("💨")
                    .font(.system(size: family == .systemLarge ? 52 : 40))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(entry.count)")
                            .font(.system(size: family == .systemLarge ? 48 : 40, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text("Fürze")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.period.widgetTitle)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(entry.slogan)
                .font(.subheadline.weight(.semibold))
                .lineLimit(family == .systemLarge ? 3 : 2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
            HStack {
                Label("Score \(entry.score)", systemImage: "sparkles")
                Spacer()
                if let updatedAt = entry.updatedAt {
                    Text(updatedAt, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct FartCounterWidget: Widget {
    let kind = "eu.rjuhas.furzapp.counter.v3"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FartWidgetProvider()) { entry in
            FartCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("RJ Furzzähler")
        .description("Furzzähler mit Notfall-Aufnahme – kompakt, gut lesbar und mit 💨.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct QuickFartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "eu.rjuhas.furzapp.quickrecord.v3") {
            ControlWidgetButton(action: OpenQuickFartRecorderIntent()) {
                Label("Furzaufnahme", systemImage: "wind")
            }
        }
        .displayName("Notfall-Furz")
        .description("Öffnet die RJ Furz-App direkt im Recorder.")
    }
}

@main
struct RJFurzWidgetBundle: WidgetBundle {
    var body: some Widget {
        FartCounterWidget()
        QuickFartControl()
    }
}
