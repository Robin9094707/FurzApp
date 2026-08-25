import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct FartEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]

    let entry: FartEntry?
    let newAudio: ImportedAudio?

    @State private var title: String
    @State private var eventDate: Date
    @State private var loudness: FartLoudness
    @State private var smellRating: Int
    @State private var personalRating: Int
    @State private var locationText: String
    @State private var contextText: String
    @State private var notes: String
    @State private var tagsText: String
    @State private var folderID: UUID?
    @State private var isFavorite: Bool
    @State private var didSave = false
    @State private var samples: [CGFloat] = []

    init(entry: FartEntry?, newAudio: ImportedAudio?) {
        self.entry = entry
        self.newAudio = newAudio
        _title = State(initialValue: entry?.title ?? newAudio?.originalName ?? "Neuer Furz")
        _eventDate = State(initialValue: entry?.eventDate ?? .now)
        _loudness = State(initialValue: entry?.loudness ?? .medium)
        _smellRating = State(initialValue: entry?.smellRating ?? 3)
        _personalRating = State(initialValue: entry?.personalRating ?? 3)
        _locationText = State(initialValue: entry?.locationText ?? "")
        _contextText = State(initialValue: entry?.contextText ?? "")
        _notes = State(initialValue: entry?.notes ?? "")
        _tagsText = State(initialValue: entry?.tags.joined(separator: ", ") ?? "")
        _folderID = State(initialValue: entry?.folderID)
        _isFavorite = State(initialValue: entry?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let filename = entry?.audioFilename ?? newAudio?.filename {
                    Section("Audio") {
                        WaveformView(samples: samples.isEmpty ? Array(repeating: 0.08, count: 60) : samples, height: 62)
                        Label(formatDuration(entry?.duration ?? newAudio?.duration ?? 0), systemImage: "waveform")
                    }
                    .task { await loadWaveform(filename: filename) }
                }

                Section("Grunddaten") {
                    TextField("Name des Furzes", text: $title)
                    DatePicker("Wann abgefurzt?", selection: $eventDate)
                    Picker("Lautstärke", selection: $loudness) {
                        ForEach(FartLoudness.allCases) { value in
                            Label(value.rawValue, systemImage: value.symbol).tag(value)
                        }
                    }
                    Toggle("Favorit", isOn: $isFavorite)
                }

                Section("Bewertung") {
                    RatingControl(title: "Wie gut war er?", value: $personalRating)
                    RatingControl(title: "Geruchsintensität", value: $smellRating, symbol: "nose.fill")
                }

                Section("Einordnung") {
                    Picker("Ordner", selection: $folderID) {
                        Text("Kein Ordner").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Label(folder.name, systemImage: folder.symbol).tag(Optional(folder.id))
                        }
                    }
                    TextField("Ort, z. B. Arbeit oder Zuhause", text: $locationText)
                    TextField("Situation, z. B. Sofa, Büro, Bus", text: $contextText)
                    TextField("Tags, mit Komma getrennt", text: $tagsText)
                }

                Section("Notizen") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                }
            }
            .navigationTitle(entry == nil ? "Furz speichern" : "Furz bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onDisappear {
                if !didSave, entry == nil, let filename = newAudio?.filename {
                    AudioFileStore.delete(filename: filename)
                }
            }
        }
    }

    private func save() {
        let tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let entry {
            entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.eventDate = eventDate
            entry.loudness = loudness
            entry.smellRating = smellRating
            entry.personalRating = personalRating
            entry.locationText = locationText
            entry.contextText = contextText
            entry.notes = notes
            entry.tags = tags
            entry.folderID = folderID
            entry.isFavorite = isFavorite
            entry.updatedAt = .now
        } else {
            let source: FartSource = newAudio == nil ? .manual : .imported
            let value = FartEntry(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                eventDate: eventDate,
                loudness: loudness,
                smellRating: smellRating,
                personalRating: personalRating,
                duration: newAudio?.duration ?? 0,
                audioFilename: newAudio?.filename,
                source: source,
                locationText: locationText,
                contextText: contextText,
                notes: notes,
                tags: tags,
                folderID: folderID,
                isFavorite: isFavorite
            )
            modelContext.insert(value)
        }
        try? modelContext.save()
        didSave = true
        Haptics.success()
        DebugLogger.shared.log("Furz-Eintrag gespeichert: \(title)")
        dismiss()
    }

    private func loadWaveform(filename: String) async {
        do {
            samples = try await WaveformAnalyzer.shared.samples(for: AudioFileStore.url(for: filename))
        } catch {
            DebugLogger.shared.log("Waveform-Fehler: \(error.localizedDescription)")
        }
    }

    private func formatDuration(_ value: Double) -> String {
        let seconds = Int(value.rounded())
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }
}

struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @StateObject private var recorder = AudioRecorder()

    @State private var title = "Frischer Furz"
    @State private var eventDate = Date.now
    @State private var loudness: FartLoudness = .medium
    @State private var smellRating = 3
    @State private var personalRating = 3
    @State private var folderID: UUID?
    @State private var locationText = ""
    @State private var contextText = ""
    @State private var notes = ""
    @State private var tagsText = ""
    @State private var isFavorite = false
    @State private var confirmCancel = false
    @State private var saveError: String?
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        recorderCard
                        if recorder.temporaryURL != nil && !recorder.isRecording {
                            metadataCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Furz aufnehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        if recorder.isRecording || recorder.temporaryURL != nil { confirmCancel = true }
                        else { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording || recorder.temporaryURL != nil)
            .confirmationDialog("Aufnahme verwerfen?", isPresented: $confirmCancel) {
                Button("Aufnahme verwerfen", role: .destructive) {
                    recorder.cancelAndCleanup()
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Die noch nicht gespeicherte Aufnahme geht verloren.")
            }
            .alert("Fehler", isPresented: Binding(
                get: { saveError != nil || recorder.errorMessage != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? recorder.errorMessage ?? "Unbekannter Fehler")
            }
            .onDisappear {
                if !didSave { recorder.cancelAndCleanup() }
            }
        }
    }

    private var recorderCard: some View {
        GlassCard {
            VStack(spacing: 18) {
                Text(recorder.isRecording ? "Ich höre zu … 💨" : recorder.temporaryURL == nil ? "Bereit für den großen Moment" : "Aufnahme im Kasten")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                WaveformView(
                    samples: recorder.levels.isEmpty ? Array(repeating: 0.06, count: 65) : recorder.levels,
                    height: 96
                )
                .animation(.snappy(duration: 0.12), value: recorder.levels)

                Text(formatTime(recorder.elapsed))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                if recorder.temporaryURL == nil {
                    Button {
                        recorder.requestPermissionAndStart()
                        Haptics.impact(.heavy)
                    } label: {
                        Label("Aufnahme starten", systemImage: "mic.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                } else if recorder.isRecording {
                    Button {
                        recorder.stop()
                        Haptics.success()
                    } label: {
                        Label("Aufnahme stoppen", systemImage: "stop.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        Button(role: .destructive) {
                            recorder.cancelAndCleanup()
                        } label: {
                            Label("Neu", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            saveRecording()
                        } label: {
                            Label("Furz sichern", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var metadataCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Details vor dem Speichern")
                    .font(.headline)

                TextField("Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Zeitpunkt", selection: $eventDate)
                Picker("Lautstärke", selection: $loudness) {
                    ForEach(FartLoudness.allCases) { value in
                        Label(value.rawValue, systemImage: value.symbol).tag(value)
                    }
                }
                RatingControl(title: "Eigene Bewertung", value: $personalRating)
                RatingControl(title: "Geruchsintensität", value: $smellRating, symbol: "nose.fill")
                Picker("Ordner", selection: $folderID) {
                    Text("Kein Ordner").tag(UUID?.none)
                    ForEach(folders) { folder in
                        Label(folder.name, systemImage: folder.symbol).tag(Optional(folder.id))
                    }
                }
                TextField("Ort", text: $locationText)
                    .textFieldStyle(.roundedBorder)
                TextField("Situation", text: $contextText)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags, z. B. Arbeit, episch", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                TextField("Notiz", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Toggle("Als Favorit markieren", isOn: $isFavorite)
            }
        }
    }

    private func saveRecording() {
        guard let tempURL = recorder.takeTemporaryURL() else { return }
        do {
            let audio = try AudioFileStore.commitRecording(from: tempURL)
            let tags = tagsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let entry = FartEntry(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unbenannter Furz" : title,
                eventDate: eventDate,
                loudness: loudness,
                smellRating: smellRating,
                personalRating: personalRating,
                duration: audio.duration,
                audioFilename: audio.filename,
                source: .recorded,
                locationText: locationText,
                contextText: contextText,
                notes: notes,
                tags: tags,
                folderID: folderID,
                isFavorite: isFavorite
            )
            modelContext.insert(entry)
            try modelContext.save()
            didSave = true
            Haptics.success()
            DebugLogger.shared.log("Eigene Furz-Aufnahme als Eintrag gespeichert")
            dismiss()
        } catch {
            saveError = error.localizedDescription
            DebugLogger.shared.log("Speicherfehler Aufnahme: \(error.localizedDescription)")
        }
    }

    private func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d.%02d", total / 60, total % 60, Int((value - floor(value)) * 100))
    }
}
