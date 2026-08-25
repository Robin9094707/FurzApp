import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Charts

struct ReminderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartReminder.createdAt) private var reminders: [FartReminder]
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
                        description: Text("Erstelle tägliche oder wochentagsbezogene Erinnerungen fürs Furz-Protokoll.")
                    )
                } else {
                    ForEach(reminders) { reminder in
                        Button {
                            editingReminder = reminder
                        } label: {
                            HStack {
                                Image(systemName: "alarm.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(reminder.title).font(.headline)
                                    Text(timeText(reminder))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { reminder.isEnabled },
                                    set: { value in
                                        reminder.isEnabled = value
                                        Task { try? await NotificationManager.shared.schedule(reminder) }
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
                Text("Die Furzwecker verwenden lokale iOS-Benachrichtigungen. Ton und Anzeige hängen von deinen iOS-Mitteilungseinstellungen ab.")
            }
        }
        .navigationTitle("Furzwecker")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) {
            ReminderEditorView(reminder: nil)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorView(reminder: reminder)
        }
        .alert("Furzwecker löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                guard let reminder = pendingDelete else { return }
                Task { await NotificationManager.shared.remove(reminderID: reminder.id) }
                modelContext.delete(reminder)
                try? modelContext.save()
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        }
    }

    private func timeText(_ reminder: FartReminder) -> String {
        let time = String(format: "%02d:%02d", reminder.hour, reminder.minute)
        if reminder.weekdaysMask == 0 { return "Täglich · \(time) Uhr" }
        let labels = [(2,"Mo"),(3,"Di"),(4,"Mi"),(5,"Do"),(6,"Fr"),(7,"Sa"),(1,"So")]
            .filter { reminder.includes(weekday: $0.0) }
            .map(\.1)
            .joined(separator: " ")
        return "\(labels) · \(time) Uhr"
    }
}

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let reminder: FartReminder?

    @State private var title: String
    @State private var time: Date
    @State private var selectedWeekdays: Set<Int>
    @State private var enabled: Bool
    @State private var errorMessage: String?

    private let days = [(2,"Mo"),(3,"Di"),(4,"Mi"),(5,"Do"),(6,"Fr"),(7,"Sa"),(1,"So")]

    init(reminder: FartReminder?) {
        self.reminder = reminder
        _title = State(initialValue: reminder?.title ?? "Furzwecker 💨")
        var components = DateComponents()
        components.hour = reminder?.hour ?? 18
        components.minute = reminder?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
        _selectedWeekdays = State(initialValue: Set((1...7).filter { reminder?.includes(weekday: $0) == true }))
        _enabled = State(initialValue: reminder?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerung") {
                    TextField("Titel", text: $title)
                    DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Aktiv", isOn: $enabled)
                }

                Section("Wiederholung") {
                    Toggle("Täglich", isOn: Binding(
                        get: { selectedWeekdays.isEmpty },
                        set: { daily in if daily { selectedWeekdays.removeAll() } else { selectedWeekdays = [2,3,4,5,6] } }
                    ))
                    if !selectedWeekdays.isEmpty {
                        HStack(spacing: 7) {
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

                Section {
                    Text("Beispiel: „Zeit für dein Furz-Protokoll 💨“ – ideal, wenn du dich regelmäßig ans Aufnehmen und Bewerten erinnern möchtest.")
                        .foregroundStyle(.secondary)
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
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let object = reminder ?? FartReminder()
        object.title = title.isEmpty ? "Furzwecker 💨" : title
        object.hour = components.hour ?? 18
        object.minute = components.minute ?? 0
        object.weekdaysMask = selectedWeekdays.reduce(0) { $0 | (1 << $1) }
        object.isEnabled = enabled
        if reminder == nil { modelContext.insert(object) }
        try? modelContext.save()

        Task {
            do {
                try await NotificationManager.shared.schedule(object)
                await MainActor.run {
                    Haptics.success()
                    dismiss()
                }
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
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmReset = false
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section("Organisation") {
                    NavigationLink { FolderManagementView() } label: {
                        Label("Furz-Ordner", systemImage: "folder.fill")
                    }
                    NavigationLink { ReminderListView() } label: {
                        Label("Furzwecker & Erinnerungen", systemImage: "alarm.fill")
                    }
                }

                Section("Daten") {
                    Button {
                        createExport()
                    } label: {
                        Label("Metadaten als JSON exportieren", systemImage: "square.and.arrow.up")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Letzten Export teilen", systemImage: "doc.badge.arrow.up")
                        }
                    }
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("Komplettes Furz-Archiv löschen", systemImage: "trash.slash.fill")
                    }
                    Text("Audio-Dateien kannst du zusätzlich direkt in jedem Furz-Eintrag teilen. Importierte oder aufgenommene Audios bleiben lokal in der App.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Diagnose") {
                    NavigationLink { DebugLogView() } label: {
                        Label("Debug-Log", systemImage: "ladybug.fill")
                    }
                }

                Section("RJ Furz-App") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Bundle", value: "eu.rjuhas.furzapp")
                    Button { showAbout = true } label: {
                        Label("Über diese Meisterleistung", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Mehr")
            .alert("Alles löschen?", isPresented: $confirmReset) {
                Button("Wirklich alles löschen", role: .destructive) { resetEverything() }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Alle Fürze, Audio-Dateien, Ordner und Furzwecker werden dauerhaft entfernt. Das kann nicht rückgängig gemacht werden.")
            }
            .alert("Export fehlgeschlagen", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "Unbekannter Fehler") }
            .sheet(isPresented: $showAbout) {
                NavigationStack {
                    ZStack {
                        RJBackground()
                        VStack(spacing: 18) {
                            Text("💨").font(.system(size: 78))
                            Text("RJ Furz-App").font(.largeTitle.bold())
                            Text("Dein völlig überqualifiziertes, persönliches Archiv für jeden legendären, leisen, lauten oder nuklearen Furz deines Lebens.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            Text("Privat · lokal · ohne Konto")
                                .font(.headline)
                        }
                        .padding()
                    }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showAbout = false } } }
                }
            }
        }
    }

    private func createExport() {
        do {
            exportURL = try ExportService.makeJSON(entries: entries)
            Haptics.success()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func resetEverything() {
        let reminderIDs = reminders.map(\.id)
        for entry in entries { modelContext.delete(entry) }
        for folder in folders { modelContext.delete(folder) }
        for reminder in reminders { modelContext.delete(reminder) }
        try? modelContext.save()
        AudioFileStore.deleteAll()
        Task {
            for id in reminderIDs { await NotificationManager.shared.remove(reminderID: id) }
        }
        Haptics.warning()
        DebugLogger.shared.log("Gesamtes Furz-Archiv zurückgesetzt")
    }
}
