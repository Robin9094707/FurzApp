import SwiftUI
import SwiftData
import MapKit

private enum FriendsMapScope: String, CaseIterable, Identifiable {
    case friends = "Freunde"
    case farts = "Fürze"
    case both = "Alles"
    var id: String { rawValue }
}

struct FriendsHomeView: View {
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var localEntries: [FartEntry]
    @StateObject private var api = PartnerAPI.shared

    @AppStorage(PartnerAPI.enabledKey) private var enabled = false
    @AppStorage(PartnerAPI.shareLocationKey) private var shareLocation = false
    @AppStorage(PartnerAPI.shareBatteryKey) private var shareBattery = false
    @AppStorage("partner.autoShareFarts") private var autoShareFarts = true

    @State private var friends: [PartnerFriend] = []
    @State private var feed: [PartnerFartDTO] = []
    @State private var leaderboard: [PartnerLeaderboardEntry] = []
    @State private var requests: [String] = []
    @State private var scope: FriendsMapScope = .both
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var locatedFriends: [PartnerFriend] {
        friends.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var locatedFarts: [PartnerFartDTO] {
        feed.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RJBackground()
                if !enabled || !api.isConnected {
                    setupView
                } else {
                    connectedView
                }
            }
            .navigationTitle("Freunde")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if enabled && api.isConnected {
                        Button { Task { await reload() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                    NavigationLink {
                        PartnerHubView()
                    } label: {
                        Image(systemName: "person.2.badge.gearshape.fill")
                    }
                    .accessibilityLabel("Furzfreunde verwalten")
                }
            }
            .task {
                if enabled && api.isConnected { await reload() }
            }
            .refreshable {
                if enabled && api.isConnected { await reload() }
            }
            .alert("Furzfreunde-Fehler", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unbekannter Fehler")
            }
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)

                VStack(spacing: 8) {
                    Text("Furzfreunde")
                        .font(.largeTitle.bold())
                    Text("Wie „Wo ist?“, nur mit deutlich fragwürdigeren Ereignissen. Sieh deine Freunde, ihre letzten Fürze und – wenn freigegeben – ihre Standorte direkt an einem Ort.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Freunde auf einer gemeinsamen Karte", systemImage: "map.fill")
                        Label("Letzte Fürze direkt im Feed und auf der Karte", systemImage: "wind")
                        Label("Standort & Akku bleiben freiwillige Freigaben", systemImage: "hand.raised.fill")
                        Label("Neue Fürze werden standardmäßig geteilt", systemImage: "arrowshape.turn.up.right.fill")
                    }
                    .font(.headline)
                }

                NavigationLink {
                    PartnerHubView()
                } label: {
                    Label(api.isConnected ? "Furzfreunde aktivieren" : "Furzfreunde einrichten", systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var connectedView: some View {
        ScrollView {
            VStack(spacing: 18) {
                mapHero
                sharingCard
                friendsSection
                requestsSection
                recentFartsSection
                leagueSection
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .overlay {
            if isLoading && friends.isEmpty && feed.isEmpty {
                ProgressView("Freunde werden geortet …")
                    .padding(18)
                    .premiumGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var mapHero: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .automatic) {
                if scope != .farts {
                    ForEach(locatedFriends) { friend in
                        if let lat = friend.latitude, let lon = friend.longitude {
                            Annotation("@\(friend.username)", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), anchor: .bottom) {
                                NavigationLink {
                                    FriendFindDetailView(friend: friend, feed: feed.filter { $0.owner == friend.username })
                                } label: {
                                    VStack(spacing: 3) {
                                        ZStack {
                                            Circle()
                                                .fill(.ultraThickMaterial)
                                                .frame(width: 48, height: 48)
                                            Image(systemName: "person.fill")
                                                .font(.title3.bold())
                                                .foregroundStyle(.tint)
                                        }
                                        Text("@\(friend.username)")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.ultraThickMaterial, in: Capsule())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if scope != .friends {
                    ForEach(locatedFarts.prefix(40)) { fart in
                        if let lat = fart.latitude, let lon = fart.longitude {
                            Annotation("Furz von @\(fart.owner)", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), anchor: .center) {
                                NavigationLink {
                                    PartnerFartDetailView(fart: fart)
                                } label: {
                                    Image(systemName: "wind.circle.fill")
                                        .font(.title2)
                                        .symbolRenderingMode(.hierarchical)
                                        .padding(4)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(height: 355)

            VStack(spacing: 10) {
                Picker("Karteninhalt", selection: $scope) {
                    ForEach(FriendsMapScope.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Label("\(friends.count) Freunde", systemImage: "person.2.fill")
                    Spacer()
                    Label("\(feed.count) Fürze · 7 Tage", systemImage: "wind")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .premiumGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var sharingCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deine Freigabe")
                            .font(.headline)
                        Text("Neue Fürze werden automatisch in den Freundeskreis gestellt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: autoShareFarts ? "checkmark.icloud.fill" : "icloud.slash.fill")
                        .font(.title2)
                        .foregroundStyle(autoShareFarts ? .green : .secondary)
                }
                Toggle("Neue Fürze automatisch teilen", isOn: $autoShareFarts)
                HStack(spacing: 8) {
                    statusPill("Standort", icon: "location.fill", active: shareLocation)
                    statusPill("Akku", icon: "battery.100percent", active: shareBattery)
                    statusPill("Verbunden", icon: "checkmark.circle.fill", active: api.isConnected)
                }
            }
        }
    }

    private func statusPill(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(active ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10), in: Capsule())
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Deine Freunde")
                    .font(.title3.bold())
                Spacer()
                NavigationLink("Verwalten") { PartnerHubView() }
                    .font(.subheadline.bold())
            }

            if friends.isEmpty {
                ContentUnavailableView("Noch keine Furzfreunde", systemImage: "person.2.slash", description: Text("Füge über „Verwalten“ deinen ersten Freund hinzu."))
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(friends.sorted(by: friendSort)) { friend in
                            NavigationLink {
                                FriendFindDetailView(friend: friend, feed: feed.filter { $0.owner == friend.username })
                            } label: {
                                FriendFindCard(friend: friend)
                                    .frame(width: 245)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var requestsSection: some View {
        if !requests.isEmpty {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(requests.count == 1 ? "1 neue Freundschaftsanfrage" : "\(requests.count) neue Freundschaftsanfragen")
                            .font(.headline)
                        Text(requests.map { "@\($0)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    NavigationLink("Öffnen") { PartnerHubView() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var recentFartsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Letzte Fürze")
                    .font(.title3.bold())
                Spacer()
                Text("7 Tage")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if feed.isEmpty {
                ContentUnavailableView("Noch windstill", systemImage: "wind", description: Text("Geteilte Fürze deiner Freunde erscheinen hier."))
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(feed.prefix(12).enumerated()), id: \.element.id) { index, fart in
                        NavigationLink {
                            PartnerFartDetailView(fart: fart)
                        } label: {
                            FriendFartRow(fart: fart)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if index < min(feed.count, 12) - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .premiumGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var leagueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Furz-Liga")
                .font(.title3.bold())
            if leaderboard.isEmpty {
                Text("Noch keine gemeinsamen Statistiken.")
                    .foregroundStyle(.secondary)
            } else {
                GlassCard {
                    VStack(spacing: 12) {
                        ForEach(Array(leaderboard.prefix(6).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 12) {
                                Text(index == 0 ? "👑" : "#\(index + 1)")
                                    .font(.headline)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(item.username)").font(.headline)
                                    Text("Ø Geruch \(item.averageSmell, specifier: "%.1f") · Ø \(item.averageRating, specifier: "%.1f")★")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.count) 💨").bold()
                                    Text("\(item.score) Pkt.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if index < min(leaderboard.count, 6) - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func friendSort(_ lhs: PartnerFriend, _ rhs: PartnerFriend) -> Bool {
        let left = lhs.locationUpdatedAt ?? lhs.lastFartAt ?? .distantPast
        let right = rhs.locationUpdatedAt ?? rhs.lastFartAt ?? .distantPast
        return left > right
    }

    @MainActor
    private func reload() async {
        guard enabled, api.isConnected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let f = api.friends()
            async let p = api.feed(days: 7)
            async let l = api.leaderboard(days: 7)
            async let r = api.friendRequests()
            friends = try await f
            feed = try await p.sorted { $0.eventDate > $1.eventDate }
            leaderboard = try await l
            requests = try await r
            PartnerPresenceCoordinator.shared.configure(entries: localEntries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FriendFindCard: View {
    let friend: PartnerFriend

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle().fill(.thinMaterial).frame(width: 54, height: 54)
                    Image(systemName: "person.fill").font(.title2).foregroundStyle(.tint)
                }
                Spacer()
                if let battery = friend.battery {
                    Label("\(battery)%", systemImage: battery < 20 ? "battery.25percent" : "battery.100percent")
                        .font(.caption.bold())
                        .foregroundStyle(battery < 20 ? .orange : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(friend.username)").font(.headline)
                if let updated = friend.locationUpdatedAt, friend.latitude != nil {
                    Label { Text(updated, style: .relative) } icon: { Image(systemName: "location.fill") }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Standort nicht geteilt", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Label("\(friend.todayCount) heute", systemImage: "wind")
                Spacer()
                Text("\(friend.score7d) Pkt.")
            }
            .font(.caption.bold())
        }
        .padding(15)
        .premiumGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct FriendFartRow: View {
    let fart: PartnerFartDTO

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.10)).frame(width: 42, height: 42)
                Image(systemName: "wind").foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("@\(fart.owner)").font(.caption.bold()).foregroundStyle(.tint)
                    Text("·")
                    Text(fart.eventDate, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
                Text(fart.title).font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(fart.loudness)
                    Text("Geruch \(fart.smellRating)/5")
                    if !fart.geofence.isEmpty { Label(fart.geofence, systemImage: "mappin.circle.fill") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if fart.latitude != nil { Image(systemName: "map.fill").foregroundStyle(.secondary) }
        }
    }
}

struct FriendFindDetailView: View {
    let friend: PartnerFriend
    let feed: [PartnerFartDTO]
    @StateObject private var api = PartnerAPI.shared
    @State private var nudgeMessage = "Zeit für einen legendären Furz 💨"
    @State private var sentMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let lat = friend.latitude, let lon = friend.longitude {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ))) {
                        Annotation("@\(friend.username)", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            ZStack {
                                Circle().fill(.ultraThickMaterial).frame(width: 54, height: 54)
                                Image(systemName: "person.fill").font(.title2).foregroundStyle(.tint)
                            }
                        }
                        ForEach(feed.filter { $0.latitude != nil && $0.longitude != nil }.prefix(15)) { fart in
                            if let fartLat = fart.latitude, let fartLon = fart.longitude {
                                Marker(fart.title, systemImage: "wind", coordinate: CLLocationCoordinate2D(latitude: fartLat, longitude: fartLon))
                            }
                        }
                    }
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("@\(friend.username)").font(.title2.bold())
                                if let updated = friend.locationUpdatedAt {
                                    Text("Standort aktualisiert \(updated.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let battery = friend.battery {
                                Label("\(battery)%", systemImage: "battery.100percent")
                                    .font(.headline)
                            }
                        }
                        Divider()
                        LabeledContent("Heute", value: "\(friend.todayCount) Fürze")
                        LabeledContent("Letzte 7 Tage", value: "\(friend.sevenDayCount) Fürze")
                        LabeledContent("Furz-Score", value: "\(friend.score7d)")
                        if let last = friend.lastFartAt {
                            LabeledContent("Letzter Furz", value: last.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Furz-Anstupser").font(.headline)
                        TextField("Nachricht", text: $nudgeMessage, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await sendNudge() }
                        } label: {
                            Label("@\(friend.username) anstupsen", systemImage: "bell.and.waves.left.and.right.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(nudgeMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Fürze von @\(friend.username)").font(.title3.bold())
                    if feed.isEmpty {
                        Text("Noch keine geteilten Fürze in den letzten 7 Tagen.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(feed.prefix(20).enumerated()), id: \.element.id) { index, fart in
                                NavigationLink {
                                    PartnerFartDetailView(fart: fart)
                                } label: {
                                    FriendFartRow(fart: fart)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                }
                                .buttonStyle(.plain)
                                if index < min(feed.count, 20) - 1 { Divider().padding(.leading, 58) }
                            }
                        }
                        .premiumGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Gesendet", isPresented: Binding(
            get: { sentMessage != nil }, set: { if !$0 { sentMessage = nil } }
        )) { Button("OK") { sentMessage = nil } } message: { Text(sentMessage ?? "") }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    @MainActor
    private func sendNudge() async {
        do {
            try await api.sendNudge(to: friend.username, message: nudgeMessage.trimmingCharacters(in: .whitespacesAndNewlines))
            sentMessage = "@\(friend.username) wurde angestupst. 💨"
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
