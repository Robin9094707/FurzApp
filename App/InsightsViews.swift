import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct FartCalendarView: View {
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var entries: [FartEntry]
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @State private var selectedDate = Date.now

    private var selectedEntries: [FartEntry] {
        entries.filter { Calendar.current.isDate($0.eventDate, inSameDayAs: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        DatePicker("Tag auswählen", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .premiumGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedDate.formatted(date: .complete, time: .omitted))
                                        .font(.headline)
                                    Text("\(selectedEntries.count) Einträge")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(selectedEntries.isEmpty ? "🌬️" : "💨")
                                    .font(.largeTitle)
                            }
                        }

                        if selectedEntries.isEmpty {
                            ContentUnavailableView(
                                "An diesem Tag war das Archiv still",
                                systemImage: "calendar.badge.minus",
                                description: Text("Wähle einen anderen Tag oder protokolliere einen Furz.")
                            )
                            .padding(.vertical, 30)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(selectedEntries) { entry in
                                    NavigationLink {
                                        FartDetailView(entry: entry)
                                    } label: {
                                        FartRow(entry: entry, folderName: folders.first(where: { $0.id == entry.folderID })?.name)
                                            .padding(14)
                                            .premiumGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Furz-Kalender")
        }
    }
}

private struct DailyFartCount: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private struct LoudnessCount: Identifiable {
    let loudness: FartLoudness
    let count: Int
    var id: String { loudness.rawValue }
}

struct StatsView: View {
    @Query private var entries: [FartEntry]
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]

    private var averageRating: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(entries.map(\.personalRating).reduce(0, +)) / Double(entries.count)
    }

    private var totalDuration: Double { entries.reduce(0) { $0 + $1.duration } }

    private var dailyCounts: [DailyFartCount] {
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: .now)
        return (0..<14).compactMap { offset -> DailyFartCount? in
            guard let date = calendar.date(byAdding: .day, value: -(13 - offset), to: startToday) else { return nil }
            let count = entries.filter { calendar.isDate($0.eventDate, inSameDayAs: date) }.count
            return DailyFartCount(date: date, count: count)
        }
    }

    private var loudnessCounts: [LoudnessCount] {
        FartLoudness.allCases.map { loudness in
            LoudnessCount(loudness: loudness, count: entries.filter { $0.loudness == loudness }.count)
        }
    }

    private var topFolder: String {
        let grouped = Dictionary(grouping: entries.compactMap { entry -> (UUID, FartEntry)? in
            guard let id = entry.folderID else { return nil }
            return (id, entry)
        }, by: { $0.0 })
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return "–" }
        return folders.first(where: { $0.id == top.key })?.name ?? "–"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(spacing: 10) {
                            MetricPill(icon: "wind", value: "\(entries.count)", label: "Gesamt")
                            MetricPill(icon: "star.fill", value: averageRating.formatted(.number.precision(.fractionLength(1))), label: "Ø Wertung")
                            MetricPill(icon: "waveform", value: durationText(totalDuration), label: "Audio")
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Letzte 14 Tage").font(.headline)
                                Chart(dailyCounts) { item in
                                    BarMark(
                                        x: .value("Tag", item.date, unit: .day),
                                        y: .value("Fürze", item.count)
                                    )
                                    .foregroundStyle(Color.accentColor.gradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .frame(height: 220)
                                .chartYAxis { AxisMarks(position: .leading) }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Lautstärke-Mix").font(.headline)
                                Chart(loudnessCounts.filter { $0.count > 0 }) { item in
                                    SectorMark(
                                        angle: .value("Anzahl", item.count),
                                        innerRadius: .ratio(0.55),
                                        angularInset: 2
                                    )
                                    .foregroundStyle(by: .value("Lautstärke", item.loudness.rawValue))
                                }
                                .frame(height: 230)
                                .chartLegend(position: .bottom, spacing: 10)
                            }
                        }

                        NavigationLink {
                            FartHeatmapView()
                        } label: {
                            GlassCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Karte & Furz-Heatmap").font(.headline)
                                        Text("Sieh, wo deine größten Windzonen liegen.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "map.fill").font(.title2).foregroundStyle(.tint)
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Archiv-Fakten").font(.headline)
                                statRow("Lieblingsordner", topFolder, "folder.fill")
                                statRow("Favoriten", "\(entries.filter(\.isFavorite).count)", "heart.fill")
                                statRow("Mit Audio", "\(entries.filter { $0.audioFilename != nil }.count)", "waveform")
                                statRow("Nukleare Fürze", "\(entries.filter { $0.loudness == .nuclear }.count)", "burst.fill")
                                statRow("Furz-Score", "\(entries.reduce(0) { $0 + $1.fartScore })", "sparkles")
                                statRow("Mit Standort", "\(entries.filter { $0.coordinate != nil }.count)", "mappin.and.ellipse")
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Furz-Statistik")
        }
    }

    private func statRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }

    private func durationText(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) s" }
        let minutes = Int(seconds / 60)
        return minutes < 60 ? "\(minutes) m" : "\(minutes / 60) h"
    }
}
