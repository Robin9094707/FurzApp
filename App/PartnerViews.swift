import SwiftUI
import SwiftData
import MapKit

struct PartnerHubView: View {
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var localEntries: [FartEntry]
    @StateObject private var api = PartnerAPI.shared
    @AppStorage(PartnerAPI.enabledKey) private var enabled = false
    @AppStorage(PartnerAPI.baseURLKey) private var baseURL = ""
    @AppStorage(PartnerAPI.usernameKey) private var username = ""
    @AppStorage(PartnerAPI.shareLocationKey) private var shareLocation = false
    @AppStorage(PartnerAPI.shareBatteryKey) private var shareBattery = false
    @AppStorage(PartnerAPI.shareAudioKey) private var shareAudio = false
    @AppStorage("partner.autoShareFarts") private var autoShareFarts = true

    @State private var password = ""
    @State private var friends: [PartnerFriend] = []
    @State private var requests: [String] = []
    @State private var feed: [PartnerFartDTO] = []
    @State private var leaderboard: [PartnerLeaderboardEntry] = []
    @State private var nudges: [PartnerNudge] = []
    @State private var addFriendName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var pendingRemove: PartnerFriend?
    @State private var pendingDeleteAccount = false
    @State private var pendingNudge: PartnerNudge?

    var body: some View {
        List {
            Section {
                Toggle("Furzfreunde aktivieren", isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        if !value {
                            LocationService.shared.setBackgroundSharing(false)
                            api.logout()
                        }
                    }
                TextField("https://furz.example.de oder IP:Port", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disabled(enabled && api.isConnected)
                TextField("Benutzername", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Server-Hauptpasswort", text: $password)
                HStack {
                    Button("Anmelden") { Task { await authenticate(register: false) } }
                        .buttonStyle(.borderedProminent)
                    Button("Konto anlegen") { Task { await authenticate(register: true) } }
                        .buttonStyle(.bordered)
                }
                .disabled(!enabled || username.trimmed.isEmpty || password.isEmpty || baseURL.trimmed.isEmpty)

                if api.isConnected {
                    Label("Verbunden als @\(api.username)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if enabled {
                    Label("Noch nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privates Furzfreunde-Backend")
            } footer: {
                Text("Standardmäßig aus. Das Hauptpasswort wird im iOS-Schlüsselbund gespeichert. Für HTTPS trägst du einfach deine Domain ein; bei HTTP musst du die vollständige http://-Adresse angeben.")
            }

            if enabled && api.isConnected {
                Section("Freigaben") {
                    Toggle("Meinen Standort teilen", isOn: $shareLocation)
                        .onChange(of: shareLocation) { _, _ in refreshPresence() }
                    Toggle("Meinen Akkustand teilen", isOn: $shareBattery)
                        .onChange(of: shareBattery) { _, _ in refreshPresence() }
                    Toggle("Audio bei geteilten Fürzen hochladen", isOn: $shareAudio)
                    Toggle("Neue Fürze standardmäßig teilen", isOn: $autoShareFarts)
                    if shareLocation {
                        Label("Hintergrund-Standort benötigt „Immer erlauben“.", systemImage: "location.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Freund hinzufügen") {
                    HStack {
                        TextField("Benutzername", text: $addFriendName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Senden") { Task { await sendFriendRequest() } }
                            .disabled(addFriendName.trimmed.isEmpty)
                    }
                }

                if !requests.isEmpty {
                    Section("Anfragen") {
                        ForEach(requests, id: \.self) { requester in
                            VStack(alignment: .leading, spacing: 10) {
                                Label("@\(requester) möchte Furzfreund werden", systemImage: "person.crop.circle.badge.plus")
                                    .font(.headline)
                                HStack {
                                    Button("Annehmen") { Task { await accept(requester) } }
                                        .buttonStyle(.borderedProminent)
                                    Button("Ablehnen", role: .destructive) { Task { await decline(requester) } }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                Section("Furzfreunde") {
                    if friends.isEmpty {
                        Text("Noch keine Furzfreunde. Schick jemandem eine Anfrage – das wird garantiert die seriöseste Freundschaftsanfrage des Tages.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friends) { friend in
                            NavigationLink {
                                PartnerFriendDetailView(friend: friend)
                            } label: {
                                PartnerFriendRow(friend: friend)
                            }
                            .swipeActions {
                                Button(role: .destructive) { pendingRemove = friend } label: {
                                    Label("Entfernen", systemImage: "person.crop.circle.badge.minus")
                                }
                            }
                        }
                    }
                }

                Section("Furz-Liga · 7 Tage") {
                    if leaderboard.isEmpty {
                        Text("Noch keine gemeinsamen Statistiken.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 12) {
                                Text(index == 0 ? "👑" : "#\(index + 1)")
                                    .frame(width: 34)
                                VStack(alignment: .leading) {
                                    Text("@\(item.username)").font(.headline)
                                    Text("Ø Geruch \(item.averageSmell, specifier: "%.1f")/5 · Ø Bewertung \(item.averageRating, specifier: "%.1f")/5")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(item.count) 💨").bold()
                                    Text("\(item.score) Pkt.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Gemeinsamer Feed") {
                    if feed.isEmpty {
                        Text("Noch keine geteilten Fürze in den letzten 7 Tagen.").foregroundStyle(.secondary)
                    } else {
                        ForEach(feed) { fart in
                            NavigationLink {
                                PartnerFartDetailView(fart: fart)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("@\(fart.owner)").font(.caption.bold()).foregroundStyle(.tint)
                                        Spacer()
                                        Text(fart.eventDate, style: .relative).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(fart.title).font(.headline)
                                    Text("\(fart.loudness) · Geruch \(fart.smellRating)/5 · \(fart.personalRating)★")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !nudges.filter({ $0.status == "pending" }).isEmpty {
                    Section("Furz-Anstupser") {
                        ForEach(nudges.filter { $0.status == "pending" }) { nudge in
                            Button {
                                pendingNudge = nudge
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("@\(nudge.from) denkt an deinen nächsten Furz", systemImage: "bell.and.waves.left.and.right.fill")
                                    Text(nudge.message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Alles neu laden") { Task { await reload() } }
                    Button("Abmelden") { api.logout() }
                    Button("Konto auf Backend löschen", role: .destructive) { pendingDeleteAccount = true }
                }
            }
        }
        .navigationTitle("Furzfreunde")
        .refreshable { await reload() }
        .task {
            if enabled && api.isConnected { await reload() }
        }
        .overlay {
            if isLoading {
                ProgressView("Synchronisiere Furzuniversum …")
                    .padding(18)
                    .premiumGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .alert("Furzfreund entfernen?", isPresented: Binding(
            get: { pendingRemove != nil },
            set: { if !$0 { pendingRemove = nil } }
        )) {
            Button("Entfernen", role: .destructive) {
                if let friend = pendingRemove { Task { await remove(friend) } }
            }
            Button("Abbrechen", role: .cancel) { pendingRemove = nil }
        } message: {
            Text("Die Freundschaft wird auf dem privaten Backend entfernt. Deine lokalen Fürze bleiben unverändert.")
        }
        .alert("Furz-Anstupser annehmen?", isPresented: Binding(
            get: { pendingNudge != nil },
            set: { if !$0 { pendingNudge = nil } }
        )) {
            Button("Wecker in 1 Minute") {
                if let nudge = pendingNudge { Task { await acceptNudge(nudge) } }
            }
            Button("Nein danke", role: .cancel) {
                if let nudge = pendingNudge { Task { await rejectNudge(nudge) } }
            }
        } message: {
            Text(pendingNudge.map { "@\($0.from): \($0.message)\n\nErst nach deiner Bestätigung wird lokal ein Alarm angelegt." } ?? "")
        }
        .alert("Konto wirklich löschen?", isPresented: $pendingDeleteAccount) {
            Button("Konto löschen", role: .destructive) { Task { await deleteAccount() } }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dein Backend-Konto, dort hochgeladene Fürze, Kommentare und Freundschaften werden gelöscht. Das lokale Archiv bleibt erhalten.")
        }
        .alert("Hinweis", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) { Button("OK") { successMessage = nil } } message: { Text(successMessage ?? "") }
        .alert("Backend-Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unbekannter Fehler") }
    }

    private func authenticate(register: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await api.registerOrLogin(register: register, username: username.trimmed, password: password)
            password = ""
            await reload()
            successMessage = register ? "Konto angelegt und verbunden. 💨" : "Erfolgreich verbunden. 💨"
        } catch { errorMessage = error.localizedDescription }
    }

    private func reload() async {
        guard enabled, api.isConnected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedFriends = api.friends()
            async let fetchedRequests = api.friendRequests()
            async let fetchedFeed = api.feed(days: 7)
            async let fetchedLeaderboard = api.leaderboard(days: 7)
            async let fetchedNudges = api.nudges()
            friends = try await fetchedFriends
            requests = try await fetchedRequests
            feed = try await fetchedFeed
            leaderboard = try await fetchedLeaderboard
            nudges = try await fetchedNudges
            refreshPresence()
        } catch { errorMessage = error.localizedDescription }
    }

    private func refreshPresence() {
        PartnerPresenceCoordinator.shared.configure(entries: localEntries)
    }

    private func sendFriendRequest() async {
        do {
            try await api.sendFriendRequest(to: addFriendName.trimmed)
            successMessage = "Freundschaftsanfrage gesendet. 💨"
            addFriendName = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func accept(_ name: String) async {
        do { try await api.acceptFriend(name); await reload() } catch { errorMessage = error.localizedDescription }
    }
    private func decline(_ name: String) async {
        do { try await api.declineFriend(name); await reload() } catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ friend: PartnerFriend) async {
        do { try await api.removeFriend(friend.username); pendingRemove = nil; await reload() } catch { errorMessage = error.localizedDescription }
    }
    private func deleteAccount() async {
        do { try await api.deleteAccount(); friends = []; feed = []; leaderboard = []; requests = []; nudges = [] } catch { errorMessage = error.localizedDescription }
    }
    private func acceptNudge(_ nudge: PartnerNudge) async {
        do {
            try await api.respondToNudge(id: nudge.id, accept: true)
            try await FartAlarmKitService.schedulePartnerNudge(title: "@\(nudge.from): \(nudge.message)")
            pendingNudge = nil
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    private func rejectNudge(_ nudge: PartnerNudge) async {
        do { try await api.respondToNudge(id: nudge.id, accept: false); pendingNudge = nil; await reload() } catch { errorMessage = error.localizedDescription }
    }
}

private struct PartnerFriendRow: View {
    let friend: PartnerFriend

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(friend.username)").font(.headline)
                HStack(spacing: 8) {
                    Text("Heute \(friend.todayCount) 💨")
                    Text("7 Tage \(friend.sevenDayCount)")
                    if let battery = friend.battery { Text("🔋\(battery)%") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if friend.latitude != nil { Image(systemName: "location.fill").foregroundStyle(.green) }
        }
    }
}

struct PartnerFriendDetailView: View {
    @StateObject private var api = PartnerAPI.shared
    let friend: PartnerFriend
    @State private var message = "Zeit für einen legendären Furz 💨"
    @State private var confirmNudge = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("@\(friend.username)").font(.title2.bold())
                        LabeledContent("Heute", value: "\(friend.todayCount) Fürze")
                        LabeledContent("7 Tage", value: "\(friend.sevenDayCount) Fürze")
                        LabeledContent("Furz-Score 7d", value: "\(friend.score7d)")
                        if let battery = friend.battery { LabeledContent("Akku", value: "\(battery) %") }
                        if let last = friend.lastFartAt { LabeledContent("Letzter Furz", value: last.formatted(date: .abbreviated, time: .shortened)) }
                        if let updated = friend.locationUpdatedAt { LabeledContent("Standort zuletzt", value: updated.formatted(date: .omitted, time: .shortened)) }
                    }
                }

                if let lat = friend.latitude, let lon = friend.longitude {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Freigegebener Standort").font(.headline)
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))) {
                                Marker(friend.username, systemImage: "person.fill", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            }
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text("Nur sichtbar, weil diese Person die Standortfreigabe selbst aktiviert hat.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Furz-Anstupser").font(.headline)
                        TextField("Nachricht", text: $message, axis: .vertical)
                        Button { confirmNudge = true } label: {
                            Label("Ans Furzen erinnern", systemImage: "bell.and.waves.left.and.right.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
        .background(RJBackground())
        .navigationTitle("Furzfreund")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Anstupser senden?", isPresented: $confirmNudge) {
            Button("Senden") { Task { await sendNudge() } }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("@\(friend.username) erhält beim nächsten Sync eine Anfrage. Ein Alarm wird auf dem anderen iPhone erst nach dessen Bestätigung erstellt.")
        }
        .alert("Furzpost", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
            Button("OK") { statusMessage = nil }
        } message: { Text(statusMessage ?? "") }
    }

    private func sendNudge() async {
        do {
            try await api.sendNudge(to: friend.username, message: message.trimmed.isEmpty ? "Zeit für einen Furz 💨" : message.trimmed)
            statusMessage = "Anstupser wurde gesendet."
        } catch { statusMessage = error.localizedDescription }
    }
}

struct PartnerFartDetailView: View {
    @StateObject private var api = PartnerAPI.shared
    @StateObject private var player = AudioPlayerService()
    let fart: PartnerFartDTO
    @State private var comment = ""
    @State private var errorMessage: String?
    @State private var isLoadingAudio = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(fart.title).font(.title2.bold())
                        Text("von @\(fart.owner)").foregroundStyle(.tint)
                        LabeledContent("Zeit", value: fart.eventDate.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Lautstärke", value: fart.loudness)
                        LabeledContent("Geruch", value: "\(fart.smellRating)/5")
                        LabeledContent("Bewertung", value: "\(fart.personalRating)/5")
                        LabeledContent("Dauer", value: fart.duration.formatted(.number.precision(.fractionLength(1))) + " s")
                        if !fart.address.isEmpty { Label(fart.address, systemImage: "mappin.and.ellipse") }
                        if !fart.context.isEmpty { Label(fart.context, systemImage: "quote.bubble") }
                        if !fart.notes.isEmpty { Text(fart.notes).foregroundStyle(.secondary) }
                    }
                }

                if fart.hasAudio {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Geteilte Aufnahme").font(.headline)
                            HStack {
                                Button {
                                    if player.isPlaying { player.pause() }
                                    else if player.duration > 0 { player.play() }
                                    else { Task { await loadAudio() } }
                                } label: {
                                    Label(player.isPlaying ? "Pause" : "Anhören", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                if isLoadingAudio { ProgressView() }
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kommentare").font(.headline)
                        ForEach(fart.comments) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(item.author)").font(.caption.bold()).foregroundStyle(.tint)
                                Text(item.text)
                                Text(item.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                        HStack {
                            TextField("Kommentar …", text: $comment)
                            Button("Senden") { Task { await sendComment() } }.disabled(comment.trimmed.isEmpty)
                        }
                    }
                }
            }
            .padding()
        }
        .background(RJBackground())
        .navigationTitle("Geteilter Furz")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func loadAudio() async {
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let url = try await api.downloadAudio(owner: fart.owner, fartID: fart.id)
            player.load(url: url)
            player.play()
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendComment() async {
        do {
            try await api.comment(owner: fart.owner, fartID: fart.id, text: comment.trimmed)
            comment = ""
            Haptics.success()
        } catch { errorMessage = error.localizedDescription }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
