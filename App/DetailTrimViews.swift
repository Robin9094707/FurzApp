import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct FartDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @StateObject private var player = AudioPlayerService()

    let entry: FartEntry
    @State private var samples: [CGFloat] = []
    @State private var showEditor = false
    @State private var showTrim = false
    @State private var confirmDelete = false

    private var folderName: String? {
        folders.first(where: { $0.id == entry.folderID })?.name
    }

    var body: some View {
        ZStack {
            RJBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if entry.audioFilename != nil { audioCard }
                    detailCard
                    if entry.coordinate != nil { FartLocationCard(entry: entry) }
                    notesCard
                    actionCard
                }
                .padding()
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    entry.isFavorite.toggle()
                    entry.updatedAt = .now
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: entry.isFavorite ? "heart.fill" : "heart")
                }
                Button("Bearbeiten") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            FartEditorView(entry: entry, newAudio: nil)
        }
        .sheet(isPresented: $showTrim) {
            TrimAudioView(entry: entry)
        }
        .alert("Diesen Furz löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) {
                player.stop()
                AudioFileStore.delete(filename: entry.audioFilename)
                modelContext.delete(entry)
                try? modelContext.save()
                Haptics.warning()
                dismiss()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Der Eintrag und die Aufnahme werden dauerhaft gelöscht.")
        }
        .onDisappear { player.stop() }
    }

    private var header: some View {
        GlassCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(entry.loudness.rawValue, systemImage: entry.loudness.symbol)
                        .font(.headline)
                        .foregroundStyle(.tint)
                    Text(entry.eventDate.formatted(date: .long, time: .shortened))
                        .font(.title3.bold())
                    if let folderName {
                        Label(folderName, systemImage: "folder.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Label("\(entry.personalRating)/5", systemImage: "star.fill")
                        .font(.title3.bold())
                    Label("\(entry.smellRating)/5", systemImage: "nose.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var audioCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                WaveformView(
                    samples: samples.isEmpty ? Array(repeating: 0.08, count: 80) : samples,
                    progress: player.duration > 0 ? player.currentTime / player.duration : 0
                )
                .task { await prepareAudio() }

                Slider(value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 0.1))

                HStack {
                    Text(formatTime(player.currentTime))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        player.toggle()
                        Haptics.impact(.light)
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 54))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(formatTime(player.duration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Picker("Tempo", selection: $player.rate) {
                        Text("0,75×").tag(Float(0.75))
                        Text("1×").tag(Float(1.0))
                        Text("1,25×").tag(Float(1.25))
                        Text("1,5×").tag(Float(1.5))
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var detailCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details").font(.headline)
                detail("Quelle", value: entry.source.rawValue, icon: "tray.and.arrow.down")
                if !entry.locationText.isEmpty { detail("Ort", value: entry.locationText, icon: "mappin.and.ellipse") }
                if !entry.contextText.isEmpty { detail("Situation", value: entry.contextText, icon: "text.bubble") }
                if !entry.tags.isEmpty { detail("Tags", value: entry.tags.joined(separator: " · "), icon: "tag") }
                if entry.duration > 0 { detail("Dauer", value: formatTime(entry.duration), icon: "timer") }
                if entry.isTrimmed { detail("Audio", value: "zugeschnitten", icon: "scissors") }
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        if !entry.notes.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notizen").font(.headline)
                    Text(entry.notes)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var actionCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                if let filename = entry.audioFilename {
                    ShareLink(item: AudioFileStore.url(for: filename)) {
                        Label("Aufnahme teilen", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        player.stop()
                        showTrim = true
                    } label: {
                        Label("Aufnahme zuschneiden", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Furz dauerhaft löschen", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detail(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func prepareAudio() async {
        guard let filename = entry.audioFilename else { return }
        let url = AudioFileStore.url(for: filename)
        player.load(url: url)
        do { samples = try await WaveformAnalyzer.shared.samples(for: url) }
        catch { DebugLogger.shared.log("Waveform Detail: \(error.localizedDescription)") }
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TrimAudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: FartEntry

    @StateObject private var player = AudioPlayerService()
    @State private var samples: [CGFloat] = []
    @State private var start: Double
    @State private var end: Double
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmTrim = false

    init(entry: FartEntry) {
        self.entry = entry
        _start = State(initialValue: 0)
        _end = State(initialValue: max(entry.duration, 0.1))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Live-Zuschnitt").font(.headline)
                                TrimWaveformSelectionView(
                                    samples: samples.isEmpty ? Array(repeating: 0.08, count: 90) : samples,
                                    startProgress: entry.duration > 0 ? start / entry.duration : 0,
                                    endProgress: entry.duration > 0 ? end / entry.duration : 1,
                                    playProgress: entry.duration > 0 ? player.currentTime / entry.duration : 0
                                )
                                .frame(height: 110)

                                HStack {
                                    Text(format(start)).monospacedDigit().font(.caption.bold())
                                    Spacer()
                                    Text("Auswahl \(format(end - start))").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(format(end)).monospacedDigit().font(.caption.bold())
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Schnittkanten").font(.headline)
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Start · \(format(start))", systemImage: "arrow.right.to.line")
                                    Slider(value: $start, in: 0...max(0.05, end - 0.05))
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Ende · \(format(end))", systemImage: "arrow.left.to.line")
                                    Slider(value: $end, in: min(entry.duration, start + 0.05)...max(entry.duration, start + 0.05))
                                }

                                HStack(spacing: 10) {
                                    Button {
                                        previewSelection()
                                    } label: {
                                        Label(player.isPlaying ? "Pause" : "Auswahl anhören", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button {
                                        start = 0
                                        end = entry.duration
                                        player.pause()
                                    } label: {
                                        Image(systemName: "arrow.counterclockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Schnitt zurücksetzen")
                                }
                                Text("Die helle Zone bleibt erhalten. Die laufende Linie zeigt dir beim Probehören exakt, wo du dich im Original befindest.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Sicheres Ersetzen", systemImage: "checkmark.shield.fill").font(.headline)
                                Text("Das Original wird erst gelöscht, wenn der neue M4A-Zuschnitt erfolgreich exportiert und geprüft wurde.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Audio zuschneiden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWorking ? "Exportiere …" : "Anwenden") { confirmTrim = true }
                        .disabled(isWorking || entry.audioFilename == nil || end - start < 0.05)
                }
            }
            .task { await prepare() }
            .onChange(of: player.currentTime) { _, value in
                if player.isPlaying && value >= end { player.pause(); player.seek(to: start) }
            }
            .onChange(of: start) { _, _ in if player.isPlaying { previewSelection() } }
            .onChange(of: end) { _, _ in if player.isPlaying { previewSelection() } }
            .onDisappear { player.stop() }
            .confirmationDialog("Audio wirklich zuschneiden?", isPresented: $confirmTrim) {
                Button("Zuschneiden") { Task { await performTrim() } }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Der markierte Bereich bleibt erhalten; das aktuelle Original wird erst nach erfolgreichem Export ersetzt.")
            }
            .alert("Zuschneiden fehlgeschlagen", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        }
    }

    private func prepare() async {
        guard let filename = entry.audioFilename else { return }
        let url = AudioFileStore.url(for: filename)
        player.load(url: url)
        do { samples = try await WaveformAnalyzer.shared.samples(for: url, count: 110) }
        catch { DebugLogger.shared.log("Trim-Waveform: \(error.localizedDescription)") }
    }

    private func previewSelection() {
        if player.isPlaying {
            player.pause()
            return
        }
        player.seek(to: start)
        player.play()
        Haptics.impact(.light)
    }

    private func performTrim() async {
        guard let oldFilename = entry.audioFilename else { return }
        player.stop()
        isWorking = true
        do {
            let result = try await AudioTrimmer.trim(filename: oldFilename, start: start, end: end)
            AudioFileStore.delete(filename: oldFilename)
            entry.audioFilename = result.filename
            entry.duration = result.duration
            entry.isTrimmed = true
            entry.updatedAt = .now
            try? modelContext.save()
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func format(_ value: Double) -> String {
        let total = max(0, Int(value.rounded(.down)))
        let hundredths = max(0, Int((value - floor(value)) * 100))
        return String(format: "%d:%02d.%02d", total / 60, total % 60, hundredths)
    }
}

private struct TrimWaveformSelectionView: View {
    let samples: [CGFloat]
    let startProgress: Double
    let endProgress: Double
    let playProgress: Double

    var body: some View {
        GeometryReader { geo in
            let count = max(samples.count, 1)
            let spacing: CGFloat = 2
            let width = max(1, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                        let p = Double(index) / Double(max(1, count - 1))
                        Capsule()
                            .fill(p >= startProgress && p <= endProgress ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: width, height: max(4, geo.size.height * min(max(value, 0.04), 1)))
                    }
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: geo.size.width * CGFloat(min(max(playProgress, 0), 1)))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
                    .offset(x: geo.size.width * CGFloat(min(max(startProgress, 0), 1)))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 3)
                    .offset(x: geo.size.width * CGFloat(min(max(endProgress, 0), 1)) - 3)
            }
        }
        .accessibilityLabel("Audio-Wellenform mit markiertem Schnittbereich")
    }
}
