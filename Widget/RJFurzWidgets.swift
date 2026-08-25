import WidgetKit
import SwiftUI
import AppIntents

private enum WidgetCounterPeriod: String, AppEnum {
    case appDefault = "default"
    case day = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case currentWeek = "week"
    case all = "all"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Zeitraum"
    static var caseDisplayRepresentations: [WidgetCounterPeriod: DisplayRepresentation] = [
        .appDefault: "App-Standard",
        .day: "Letzte 24 Stunden",
        .sevenDays: "Letzte 7 Tage",
        .thirtyDays: "Letzte 30 Tage",
        .currentWeek: "Diese Woche",
        .all: "Insgesamt"
    ]

    var shared: RJFurzShared.Period {
        if self == .appDefault { return RJFurzShared.defaultPeriod }
        return RJFurzShared.Period(rawValue: rawValue) ?? .sevenDays
    }

    var shortTitle: String {
        switch self {
        case .appDefault:
            switch RJFurzShared.defaultPeriod {
            case .day: "24 h"
            case .sevenDays: "7 Tage"
            case .thirtyDays: "30 Tage"
            case .currentWeek: "Woche"
            case .all: "Gesamt"
            }
        case .day: "24 h"
        case .sevenDays: "7 Tage"
        case .thirtyDays: "30 Tage"
        case .currentWeek: "Woche"
        case .all: "Gesamt"
        }
    }
}

private struct FartCounterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Furzzähler"
    static var description = IntentDescription("Wähle, welchen Zeitraum das Widget zählen soll.")

    @Parameter(title: "Zeitraum", default: .appDefault)
    var period: WidgetCounterPeriod
}

private struct FartWidgetEntry: TimelineEntry {
    let date: Date
    let count: Int
    let score: Int
    let slogan: String
    let period: WidgetCounterPeriod
}

private struct FartWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FartWidgetEntry {
        FartWidgetEntry(date: .now, count: 7, score: 420, slogan: "Windpark RJ ist online.", period: .sevenDays)
    }

    func snapshot(for configuration: FartCounterIntent, in context: Context) async -> FartWidgetEntry {
        makeEntry(configuration)
    }

    func timeline(for configuration: FartCounterIntent, in context: Context) async -> Timeline<FartWidgetEntry> {
        let entry = makeEntry(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func makeEntry(_ configuration: FartCounterIntent) -> FartWidgetEntry {
        let count = RJFurzShared.count(for: configuration.period.shared)
        let score = RJFurzShared.score
        return FartWidgetEntry(
            date: .now,
            count: count,
            score: score,
            slogan: RJFurzShared.slogan(count: count, score: score),
            period: configuration.period
        )
    }
}

private struct FartCounterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FartWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wind")
                    .font(.title2.bold())
                Text("RJ Furz")
                    .font(.headline)
                Spacer()
                Button(intent: QuickFartRecordIntent()) {
                    Image(systemName: "mic.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sofort Furzaufnahme starten")
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(entry.count)")
                    .font(.system(size: family == .systemSmall ? 42 : 48, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("Fürze")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(entry.period.shortTitle)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if family != .systemSmall {
                Divider()
                HStack {
                    Label("Score \(entry.score)", systemImage: "sparkles")
                        .font(.caption.bold())
                    Spacer()
                    Text("Tippen: aufnehmen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.slogan)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(family == .systemLarge ? 3 : 2)
            } else {
                Text(entry.slogan)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.purple.opacity(0.25), Color.orange.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct FartCounterWidget: Widget {
    let kind = "eu.rjuhas.furzapp.counter"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FartCounterIntent.self, provider: FartWidgetProvider()) { entry in
            FartCounterWidgetView(entry: entry)
        }
        .configurationDisplayName("RJ Furzzähler")
        .description("Zählt deine Fürze und startet im Notfall sofort eine Aufnahme.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct QuickFartControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "eu.rjuhas.furzapp.quickrecord") {
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
