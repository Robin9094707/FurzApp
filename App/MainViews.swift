import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allEntries: [FartEntry]
    @Query private var allReminders: [FartReminder]
    @State private var selectedTab = 0
    @State private var showRecorder = false
    @State private var showImporter = false
    @State private var importedAudio: ImportedAudio?
    @State private var importError: String?
    @State private var autoStartRecorder = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(showRecorder: $showRecorder, showImporter: $showImporter) {
                autoStartRecorder = true
                showRecorder = true
                Haptics.impact(.heavy)
            }
                .tabItem { Label("Heute", systemImage: "sparkles") }
                .tag(0)

            LibraryView(showRecorder: $showRecorder, showImporter: $showImporter)
                .tabItem { Label("Archiv", systemImage: "waveform.badge.magnifyingglass") }
                .tag(1)

            FriendsHomeView()
                .tabItem { Label("Freunde", systemImage: "person.2.fill") }
                .tag(2)

            StatsView()
                .tabItem { Label("Statistik", systemImage: "chart.xyaxis.line") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Mehr", systemImage: "gearshape") }
                .tag(4)
        }
        .sheet(isPresented: $showRecorder, onDismiss: { autoStartRecorder = false }) {
            RecorderView(autoStart: autoStartRecorder)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    importedAudio = try AudioFileStore.importAudio(from: url)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importedAudio) { audio in
            FartEditorView(entry: nil, newAudio: audio)
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Unbekannter Fehler")
        }
        .onAppear { refreshSharedState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSharedState() }
        }
        .onChange(of: allEntries.count) { _, _ in refreshSharedState() }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "rjfurz", url.host?.lowercased() == "record" else { return }
            autoStartRecorder = true
            showRecorder = true
            Haptics.impact(.heavy)
        }
    }

    private func refreshSharedState() {
        WidgetSnapshotUpdater.refresh(entries: allEntries)
        PartnerPresenceCoordinator.shared.configure(entries: allEntries)
        Task {
            await NotificationManager.shared.refreshInactivity(reminders: allReminders, entries: allEntries)
            await PartnerAPI.shared.processRemoteCommands(lastFartAt: allEntries.map(\.eventDate).max())
        }
        if QuickRecordRequest.consumeIfRecent() {
            autoStartRecorder = true
            showRecorder = true
        }
    }

}

struct DashboardView: View {
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var entries: [FartEntry]
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @Binding var showRecorder: Bool
    @Binding var showImporter: Bool
    let onInstantRecord: () -> Void

    private var todayEntries: [FartEntry] {
        entries.filter { Calendar.current.isDateInToday($0.eventDate) }
    }

    private var averageRating: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(entries.map(\.personalRating).reduce(0, +)) / Double(entries.count)
    }

    private var totalDuration: Double {
        entries.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        instantRecordButton
                        hero
                        metrics
                        quickActions
                        recentSection
                    }
                    .padding()
                }
            }
            .navigationTitle("RJ Furz-App 💨")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onInstantRecord()
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                    .accessibilityLabel("Furz aufnehmen")
                }
            }
        }
    }

    private var instantRecordButton: some View {
        Button(action: onInstantRecord) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 116, height: 116)
                        .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
                        .shadow(radius: 18, y: 8)
                    Text("💨")
                        .font(.system(size: 58))
                }
                Text("Sofort aufnehmen")
                    .font(.headline)
                Text("Ein Tipp – und der Recorder läuft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Furz sofort aufnehmen")
    }

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wind")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text("💨")
                        .font(.system(size: 38))
                }
                Text(todayEntries.isEmpty ? "Noch still heute?" : "Heute schon \(todayEntries.count)× dokumentiert")
                    .font(.title2.bold())
                Text(todayEntries.isEmpty
                     ? "Wenn der nächste kommt: aufnehmen, bewerten und für die Ewigkeit archivieren."
                     : "Dein persönliches Furz-Archiv wächst. Wissenschaftlich fragwürdig, historisch unbezahlbar.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricPill(icon: "calendar", value: "\(todayEntries.count)", label: "Heute")
            MetricPill(icon: "star.fill", value: averageRating.formatted(.number.precision(.fractionLength(1))), label: "Ø Bewertung")
            MetricPill(icon: "waveform", value: formatDuration(totalDuration), label: "Audio")
        }
    }

    private var quickActions: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Schnellaktionen")
                    .font(.headline)
                HStack(spacing: 10) {
                    quickButton("Aufnehmen", icon: "mic.fill") { onInstantRecord() }
                    quickButton("Import", icon: "square.and.arrow.down") { showImporter = true }
                }
                NavigationLink {
                    ReminderListView()
                } label: {
                    Label("Furzwecker & Erinnerungen", systemImage: "alarm.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    FartCalendarView()
                } label: {
                    Label("Furz-Kalender öffnen", systemImage: "calendar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func quickButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Zuletzt gefurzt")
                    .font(.title3.bold())
                Spacer()
                if !entries.isEmpty {
                    NavigationLink("Alle") { LibraryView(showRecorder: $showRecorder, showImporter: $showImporter) }
                        .font(.subheadline.bold())
                }
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    "Noch kein Furz im Archiv",
                    systemImage: "wind",
                    description: Text("Deine erste Aufnahme erscheint hier.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.prefix(4)) { entry in
                        NavigationLink {
                            FartDetailView(entry: entry)
                        } label: {
                            FartRow(entry: entry, folderName: folders.first(where: { $0.id == entry.folderID })?.name)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if entry.id != entries.prefix(4).last?.id { Divider().padding(.leading, 76) }
                    }
                }
                .padding(.vertical, 4)
                .premiumGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func formatDuration(_ value: Double) -> String {
        if value < 60 { return "\(Int(value.rounded())) s" }
        return "\(Int(value / 60)) m"
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FartEntry]
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @Binding var showRecorder: Bool
    @Binding var showImporter: Bool

    @State private var searchText = ""
    @State private var sort: FartSort = .newest
    @State private var favoritesOnly = false
    @State private var selectedFolderID: UUID?
    @State private var selectedLoudness: FartLoudness?
    @State private var showManualEditor = false
    @State private var pendingDelete: FartEntry?

    private var filtered: [FartEntry] {
        var value = entries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.title.localizedCaseInsensitiveContains(searchText) ||
                entry.notes.localizedCaseInsensitiveContains(searchText) ||
                entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            let matchesFavorite = !favoritesOnly || entry.isFavorite
            let matchesFolder = selectedFolderID == nil || entry.folderID == selectedFolderID
            let matchesLoudness = selectedLoudness == nil || entry.loudness == selectedLoudness
            return matchesSearch && matchesFavorite && matchesFolder && matchesLoudness
        }

        switch sort {
        case .newest: value.sort { $0.eventDate > $1.eventDate }
        case .oldest: value.sort { $0.eventDate < $1.eventDate }
        case .rating: value.sort { $0.personalRating > $1.personalRating }
        case .loudness: value.sort { $0.loudness.score > $1.loudness.score }
        case .duration: value.sort { $0.duration > $1.duration }
        }
        return value
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                VStack(spacing: 0) {
                    filterStrip
                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filtered) { entry in
                                NavigationLink {
                                    FartDetailView(entry: entry)
                                } label: {
                                    FartRow(entry: entry, folderName: folders.first(where: { $0.id == entry.folderID })?.name)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        entry.isFavorite.toggle()
                                        entry.updatedAt = .now
                                    } label: {
                                        Label("Favorit", systemImage: entry.isFavorite ? "heart.slash" : "heart")
                                    }
                                    .tint(.pink)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = entry
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Furz-Archiv")
            .searchable(text: $searchText, prompt: "Name, Notiz oder Tag")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { showRecorder = true } label: { Label("Aufnehmen", systemImage: "mic.fill") }
                        Button { showImporter = true } label: { Label("Audio importieren", systemImage: "square.and.arrow.down") }
                        Button { showManualEditor = true } label: { Label("Ohne Audio protokollieren", systemImage: "square.and.pencil") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Picker("Sortierung", selection: $sort) {
                            ForEach(FartSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Nur Favoriten", isOn: $favoritesOnly)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .sheet(isPresented: $showManualEditor) {
                FartEditorView(entry: nil, newAudio: nil)
            }
            .alert("Furz wirklich löschen?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Löschen", role: .destructive) {
                    if let entry = pendingDelete {
                        AudioFileStore.delete(filename: entry.audioFilename)
                        modelContext.delete(entry)
                        Haptics.warning()
                    }
                    pendingDelete = nil
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Aufnahme und Eintrag werden dauerhaft entfernt.")
            }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Alle Ordner") { selectedFolderID = nil }
                    ForEach(folders) { folder in
                        Button(folder.name) { selectedFolderID = folder.id }
                    }
                } label: {
                    Label(folderFilterName, systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Alle Lautstärken") { selectedLoudness = nil }
                    ForEach(FartLoudness.allCases) { loudness in
                        Button(loudness.rawValue) { selectedLoudness = loudness }
                    }
                } label: {
                    Label(selectedLoudness?.rawValue ?? "Lautstärke", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)

                if favoritesOnly || selectedFolderID != nil || selectedLoudness != nil {
                    Button("Filter löschen", systemImage: "xmark.circle.fill") {
                        favoritesOnly = false
                        selectedFolderID = nil
                        selectedLoudness = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var folderFilterName: String {
        guard let selectedFolderID else { return "Ordner" }
        return folders.first(where: { $0.id == selectedFolderID })?.name ?? "Ordner"
    }
}
