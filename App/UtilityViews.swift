import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartReminder.createdAt) private var reminders: [FartReminder]
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var entries: [FartEntry]
    @State private var showEditor = false
    @State private var editingReminder: FartReminder?
    @State private var pendingDelete: FartReminder?

    var body: some View {
        List {
            Section {
                if reminders.isEmpty {
                    ContentUnavailableView(
                        "Noch kein Furzwecker",
                        systemImage: "alarm",
                        description: Text("Erstelle echte AlarmKit-Wecker, normale Erinnerungen oder einen Windstille-Alarm nach längerer Inaktivität.")
                    )
                } else {
                    ForEach(reminders) { reminder in
                        Button { editingReminder = reminder } label: {
                            HStack(spacing: 12) {
                                Image(systemName: reminder.mode == .inactivity ? "wind.circle.fill" : (reminder.useAlarmKit ? "alarm.waves.left.and.right.fill" : "alarm.fill"))
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reminder.title).font(.headline)
                                    Text(description(reminder))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { reminder.isEnabled },
                                    set: { value in
                                        reminder.isEnabled = value
                                        try? modelContext.save()
                                        Task { await reschedule(reminder) }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { pendingDelete = reminder } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Deine Erinnerungen")
            } footer: {
                Text("AlarmKit erzeugt auf iOS 26 einen echten Systemalarm. Normale Erinnerungen verwenden lokale Mitteilungen. Der Windstille-Alarm erinnert dich erst, wenn länger kein Furz eingetragen wurde.")
            }
        }
        .navigationTitle("Furzwecker")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) { ReminderEditorView(reminder: nil) }
        .sheet(item: $editingReminder) { ReminderEditorView(reminder: $0) }
        .alert("Furzwecker löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                guard let reminder = pendingDelete else { return }
                Task {
                    await NotificationManager.shared.remove(reminderID: reminder.id)
                    await NotificationManager.shared.removeInactivity(reminderID: reminder.id)
                    FartAlarmKitService.cancel(reminderID: reminder.id)
                }
                modelContext.delete(reminder)
                try? modelContext.save()
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        }
    }

    private func description(_ reminder: FartReminder) -> String {
        if reminder.mode == .inactivity {
            return "Nach \(reminder.inactivityHours) h Windstille"
        }
        let time = String(format: "%02d:%02d", reminder.hour, reminder.minute)
        let engine = reminder.useAlarmKit ? "AlarmKit" : "Mitteilung"
        if reminder.weekdaysMask == 0 { return "Täglich · \(time) · \(engine)" }
        let labels = [(2,"Mo"),(3,"Di"),(4,"Mi"),(5,"Do"),(6,"Fr"),(7,"Sa"),(1,"So")]
            .filter { reminder.includes(weekday: $0.0) }.map(\.1).joined(separator: " ")
        return "\(labels) · \(time) · \(engine)"
    }

    private func reschedule(_ reminder: FartReminder) async {
        if reminder.mode == .inactivity {
            FartAlarmKitService.cancel(reminderID: reminder.id)
            await NotificationManager.shared.remove(reminderID: reminder.id)
            try? await NotificationManager.shared.scheduleInactivity(reminder, lastFartDate: entries.map(\.eventDate).max())
        } else if reminder.useAlarmKit {
            await NotificationManager.shared.remove(reminderID: reminder.id)
            await NotificationManager.shared.removeInactivity(reminderID: reminder.id)
            try? await FartAlarmKitService.schedule(reminder: reminder)
        } else {
            FartAlarmKitService.cancel(reminderID: reminder.id)
            await NotificationManager.shared.removeInactivity(reminderID: reminder.id)
            try? await NotificationManager.shared.schedule(reminder)
        }
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var entries: [FartEntry]
    let reminder: FartReminder?

    @State private var title: String
    @State private var mode: ReminderMode
    @State private var time: Date
    @State private var selectedWeekdays: Set<Int>
    @State private var enabled: Bool
    @State private var useAlarmKit: Bool
    @State private var inactivityHours: Int
    @State private var errorMessage: String?

    private let days = [(2,"Mo"),(3,"Di"),(4,"Mi"),(5,"Do"),(6,"Fr"),(7,"Sa"),(1,"So")]

    init(reminder: FartReminder?) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "Furzwecker 💨")
        _mode = State(initialValue: reminder?.mode ?? .clock)
        var components = DateComponents()
        components.hour = reminder?.hour ?? 18
        components.minute = reminder?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _selectedWeekdays = State(initialValue: Set((1...7).filter { reminder?.includes(weekday: $0) == true }))
        _enabled = State(initialValue: reminder?.isEnabled ?? true)
        _useAlarmKit = State(initialValue: reminder?.useAlarmKit ?? true)
        _inactivityHours = State(initialValue: reminder?.inactivityHours ?? 12)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Typ") {
                    Picker("Erinnerungstyp", selection: $mode) {
                        ForEach(ReminderMode.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Aktiv", isOn: $enabled)
                }

                if mode == .clock {
                    Section("Wecker") {
                        TextField("Titel", text: $title)
                        DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                        Toggle("Echten Apple-Alarm verwenden", isOn: $useAlarmKit)
                        Text(useAlarmKit ? "AlarmKit kann wie ein echter Wecker auf dem Sperrbildschirm erscheinen." : "Verwendet eine normale lokale iOS-Mitteilung.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Section("Wiederholung") {
                        Toggle("Täglich", isOn: Binding(
                            get: { selectedWeekdays.isEmpty },
                            set: { daily in selectedWeekdays = daily ? [] : [2,3,4,5,6] }
                        ))
                        if !selectedWeekdays.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(days, id: \.0) { day in
                                    Button(day.1) {
                                        if selectedWeekdays.contains(day.0) { selectedWeekdays.remove(day.0) }
                                        else { selectedWeekdays.insert(day.0) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(selectedWeekdays.contains(day.0) ? Color.accentColor : Color.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Section("Windstille-Alarm") {
                        TextField("Titel", text: $title)
                        Stepper("Nach \(inactivityHours) Stunden ohne Eintrag", value: $inactivityHours, in: 1...168)
                        Text("Sobald du wieder einen Furz speicherst, startet dieser Zeitraum neu. Dieser Typ verwendet bewusst eine normale Mitteilung statt einen überraschenden Vollbild-Wecker.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(reminder == nil ? "Neuer Furzwecker" : "Furzwecker bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() } }
            }
            .alert("Konnte nicht geplant werden", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let object = reminder ?? FartReminder()
        object.title = title.trimmed.isEmpty ? (mode == .inactivity ? "Schon gefurzt? 💨" : "Furzwecker 💨") : title.trimmed
        object.hour = components.hour ?? 18
        object.minute = components.minute ?? 0
        object.weekdaysMask = selectedWeekdays.reduce(0) { $0 | (1 << $1) }
        object.isEnabled = enabled
        object.mode = mode
        object.inactivityHours = inactivityHours
        object.useAlarmKit = mode == .clock && useAlarmKit
        if reminder == nil { modelContext.insert(object) }
        try? modelContext.save()

        Task {
            do {
                await NotificationManager.shared.remove(reminderID: object.id)
                await NotificationManager.shared.removeInactivity(reminderID: object.id)
                FartAlarmKitService.cancel(reminderID: object.id)
                if object.isEnabled {
                    if object.mode == .inactivity {
                        try await NotificationManager.shared.scheduleInactivity(object, lastFartDate: entries.map(\.eventDate).max())
                    } else if object.useAlarmKit {
                        try await FartAlarmKitService.schedule(reminder: object)
                    } else {
                        try await NotificationManager.shared.schedule(object)
                    }
                }
                await MainActor.run { Haptics.success(); dismiss() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

struct FolderManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartFolder.name) private var folders: [FartFolder]
    @Query private var entries: [FartEntry]
    @State private var showAdd = false
    @State private var pendingDelete: FartFolder?

    var body: some View {
        List {
            if folders.isEmpty {
                ContentUnavailableView(
                    "Noch keine Ordner",
                    systemImage: "folder.badge.plus",
                    description: Text("Lege z. B. „Arbeit“, „Zuhause“, „Harte Fürze“ oder „Leise Legenden“ an.")
                )
            } else {
                ForEach(folders) { folder in
                    HStack {
                        Label(folder.name, systemImage: folder.symbol)
                        Spacer()
                        Text("\(entries.filter { $0.folderID == folder.id }.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = folder } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Ordner")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "folder.badge.plus") }
            }
        }
        .sheet(isPresented: $showAdd) { FolderEditorView() }
        .alert("Ordner löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                guard let folder = pendingDelete else { return }
                entries.filter { $0.folderID == folder.id }.forEach { $0.folderID = nil }
                modelContext.delete(folder)
                try? modelContext.save()
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Die Fürze bleiben erhalten und werden nur aus diesem Ordner entfernt.")
        }
    }
}

private struct FolderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var symbol = "folder.fill"
    private let symbols = ["folder.fill", "house.fill", "briefcase.fill", "flame.fill", "snowflake", "bolt.fill", "moon.stars.fill", "car.fill", "figure.walk", "party.popper.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ordner") {
                    TextField("Name", text: $name)
                    Picker("Symbol", selection: $symbol) {
                        ForEach(symbols, id: \.self) { value in
                            Label(value, systemImage: value).tag(value)
                        }
                    }
                }
            }
            .navigationTitle("Neuer Ordner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        modelContext.insert(FartFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol))
                        try? modelContext.save()
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct DebugLogView: View {
    @State private var text = DebugLogger.shared.text()
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Debug-Log")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Neu laden") { text = DebugLogger.shared.text() }
                Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
            }
        }
        .alert("Debug-Log löschen?", isPresented: $confirmClear) {
            Button("Löschen", role: .destructive) {
                DebugLogger.shared.clear()
                text = "Noch keine Debug-Einträge."
            }
            Button("Abbrechen", role: .cancel) { }
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FartEntry]
    @Query private var folders: [FartFolder]
    @Query private var reminders: [FartReminder]
    @Query private var geofences: [FartGeofence]
    @StateObject private var locationService = LocationService.shared
    @AppStorage("location.captureEnabled") private var captureLocation = false
    @AppStorage("widget.counterPeriod") private var widgetCounterPeriod = "7d"
    @AppStorage(PartnerAPI.enabledKey) private var partnerEnabled = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmReset = false
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section("Organisation") {
                    NavigationLink { FolderManagementView() } label: { Label("Furz-Ordner", systemImage: "folder.fill") }
                    NavigationLink { ReminderListView() } label: { Label("Furzwecker & Windstille-Alarm", systemImage: "alarm.waves.left.and.right.fill") }
                    NavigationLink { GeofenceListView() } label: { Label("Furz-Orte / Geofences", systemImage: "mappin.and.ellipse") }
                    NavigationLink { FartHeatmapView() } label: { Label("Karte & Furz-Heatmap", systemImage: "map.fill") }
                }

                Section("Standort · optional") {
                    Toggle("Standort beim Furz erfassen", isOn: $captureLocation)
                        .onChange(of: captureLocation) { _, enabled in
                            if enabled { locationService.requestWhenInUse() }
                        }
                    LabeledContent("Berechtigung", value: locationAuthorizationText)
                    Text("Die lokale Standorterfassung ist unabhängig vom Furzfreunde-Backend. Ohne separate Freigabe wird kein Standort hochgeladen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Widgets & Schnellaufnahme") {
                    Picker("Standard-Zeitraum", selection: $widgetCounterPeriod) {
                        Text("24 Stunden").tag("24h")
                        Text("7 Tage").tag("7d")
                        Text("30 Tage").tag("30d")
                        Text("Diese Woche").tag("week")
                        Text("Insgesamt").tag("all")
                    }
                    .onChange(of: widgetCounterPeriod) { _, value in
                        RJFurzShared.defaultPeriod = RJFurzShared.Period(rawValue: value) ?? .sevenDays
                        WidgetSnapshotUpdater.refresh(entries: entries)
                    }
                    .onAppear {
                        RJFurzShared.defaultPeriod = RJFurzShared.Period(rawValue: widgetCounterPeriod) ?? .sevenDays
                    }
                    Text("Das Home-Screen-Widget kann seinen Zeitraum zusätzlich direkt beim Bearbeiten des Widgets wählen. Der 💨-Knopf öffnet die App sofort im Recorder; im Kontrollzentrum gibt es denselben Notfall-Knopf.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Furzfreunde · privat") {
                    NavigationLink { PartnerHubView() } label: {
                        Label("Furzfreunde & Partner-Dashboard", systemImage: "person.2.wave.2.fill")
                    }
                    LabeledContent("Backend", value: partnerEnabled ? "Aktiviert" : "Aus")
                    Text("Optionales eigenes Python-Backend für Freunde, Feed, Rangliste, Kommentare, freiwilligen Standort/Akku und Furz-Anstupser.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Daten") {
                    Button { createExport() } label: { Label("Metadaten als JSON exportieren", systemImage: "square.and.arrow.up") }
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Letzten Export teilen", systemImage: "doc.badge.arrow.up") }
                    }
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Komplettes Furz-Archiv löschen", systemImage: "trash.slash.fill")
                    }
                    Text("Audio-Dateien kannst du direkt aus jedem Eintrag teilen. Standortdaten sind Teil deines lokalen Archivs und werden beim Komplett-Reset ebenfalls entfernt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Diagnose") {
                    NavigationLink { DebugLogView() } label: { Label("Debug-Log", systemImage: "ladybug.fill") }
                }

                Section("RJ Furz-App") {
                    LabeledContent("Version", value: "2.0")
                    LabeledContent("Bundle", value: "eu.rjuhas.furzapp")
                    LabeledContent("100+ Sprüche", value: "Eingebaut")
                    Button { showAbout = true } label: { Label("Über diese Meisterleistung", systemImage: "info.circle") }
                }
            }
            .navigationTitle("Mehr")
            .alert("Alles löschen?", isPresented: $confirmReset) {
                Button("Wirklich alles löschen", role: .destructive) { resetEverything() }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Alle lokalen Fürze, Audio-Dateien, Ordner, Furzwecker und Geofences werden dauerhaft entfernt. Ein optionales Backend-Konto wird NICHT automatisch gelöscht.")
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } }
            )) { Button("OK", role: .cancel) { exportError = nil } } message: { Text(exportError ?? "Unbekannter Fehler") }
            .sheet(isPresented: $showAbout) {
                NavigationStack {
                    ZStack {
                        RJBackground()
                        VStack(spacing: 18) {
                            Text("💨").font(.system(size: 78))
                            Text("RJ Furz-App 2.0").font(.largeTitle.bold())
                            Text("Recorder, Furz-Orte, Heatmap, Widget-Notfallknopf, AlarmKit und – völlig freiwillig – ein privates Furzfreunde-Universum.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                            Text("Lokal zuerst · Freigaben immer optional")
                                .font(.headline)
                        }.padding()
                    }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showAbout = false } } }
                }
            }
        }
    }

    private var locationAuthorizationText: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways: "Immer"
        case .authorizedWhenInUse: "Beim Verwenden"
        case .denied: "Nicht erlaubt"
        case .restricted: "Eingeschränkt"
        case .notDetermined: "Noch nicht gefragt"
        @unknown default: "Unbekannt"
        }
    }

    private func createExport() {
        do { exportURL = try ExportService.makeJSON(entries: entries); Haptics.success() }
        catch { exportError = error.localizedDescription }
    }

    private func resetEverything() {
        let reminderIDs = reminders.map(\.id)
        for entry in entries { modelContext.delete(entry) }
        for folder in folders { modelContext.delete(folder) }
        for reminder in reminders { modelContext.delete(reminder) }
        for geofence in geofences { modelContext.delete(geofence) }
        try? modelContext.save()
        AudioFileStore.deleteAll()
        WidgetSnapshotUpdater.refresh(entries: [])
        Task {
            for id in reminderIDs {
                await NotificationManager.shared.remove(reminderID: id)
                await NotificationManager.shared.removeInactivity(reminderID: id)
                FartAlarmKitService.cancel(reminderID: id)
            }
        }
        Haptics.warning()
        DebugLogger.shared.log("Gesamtes lokales Furz-Archiv v2 zurückgesetzt")
    }
}
