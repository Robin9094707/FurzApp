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
    let entry: FartEntry

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
            Form {
                Section("Bereich") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Start")
                            Spacer()
                            Text(format(start)).monospacedDigit()
                        }
                        Slider(value: $start, in: 0...max(0.1, end - 0.1))
                        HStack {
                            Text("Ende")
                            Spacer()
                            Text(format(end)).monospacedDigit()
                        }
                        Slider(value: $end, in: min(entry.duration, start + 0.1)...max(entry.duration, start + 0.1))
                    }
                }
                Section {
                    Text("Der gewählte Bereich bleibt erhalten. Das Original wird erst nach erfolgreichem Export ersetzt.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Audio zuschneiden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWorking ? "Exportiere …" : "Anwenden") { confirmTrim = true }
                        .disabled(isWorking || entry.audioFilename == nil || end - start < 0.1)
                }
            }
            .confirmationDialog("Audio wirklich zuschneiden?", isPresented: $confirmTrim) {
                Button("Zuschneiden") { Task { await performTrim() } }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Das aktuelle Original wird nach erfolgreichem Zuschnitt gelöscht.")
            }
            .alert("Zuschneiden fehlgeschlagen", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        }
    }

    private func performTrim() async {
        guard let oldFilename = entry.audioFilename else { return }
        isWorking = true
        do {
            let result = try await AudioTrimmer.trim(filename: oldFilename, start: start, end: end)
            AudioFileStore.delete(filename: oldFilename)
            entry.audioFilename = result.filename
            entry.duration = result.duration
            entry.isTrimmed = true
            entry.updatedAt = .now
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func format(_ value: Double) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
