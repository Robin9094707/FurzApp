import Foundation
import CoreLocation
import MapKit
import UIKit
import Security
import WidgetKit

// MARK: - Location, address resolution and geofences

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?
    @Published private(set) var isBackgroundSharing = false

    private let manager = CLLocationManager()
    var onBackgroundLocation: ((CLLocation) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        authorizationStatus = manager.authorizationStatus
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func requestCurrentLocation() {
        if authorizationStatus == .notDetermined { requestWhenInUse() }
        manager.requestLocation()
    }

    func setBackgroundSharing(_ enabled: Bool) {
        isBackgroundSharing = enabled
        if enabled {
            if authorizationStatus != .authorizedAlways { requestAlways() }
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 100
            manager.pausesLocationUpdatesAutomatically = true
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
            DebugLogger.shared.log("Hintergrund-Standortfreigabe aktiviert")
        } else {
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            DebugLogger.shared.log("Hintergrund-Standortfreigabe deaktiviert")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last else { return }
        location = newest
        if isBackgroundSharing { onBackgroundLocation?(newest) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
        DebugLogger.shared.log("Standortfehler: \(error.localizedDescription)")
    }

    var batteryPercent: Int? {
        let value = UIDevice.current.batteryLevel
        guard value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    var batteryStateText: String {
        switch UIDevice.current.batteryState {
        case .charging: "charging"
        case .full: "full"
        case .unplugged: "unplugged"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}

enum AddressResolver {
    static func reverse(_ location: CLLocation) async -> String {
        // CLGeocoder bleibt als Kompatibilitäts-Fallback verfügbar. iOS 26 markiert ihn
        // zugunsten MapKit als deprecated, entfernt ihn aber nicht.
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "de_DE"))
            guard let p = placemarks.first else { return "" }
            let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            let city = [p.postalCode, p.locality].compactMap { $0 }.joined(separator: " ")
            return [street, city, p.country ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        } catch {
            DebugLogger.shared.log("Reverse-Geocoding fehlgeschlagen: \(error.localizedDescription)")
            return ""
        }
    }
}

enum GeofenceMatcher {
    static func name(for location: CLLocation, geofences: [FartGeofence]) -> String {
        geofences.compactMap { fence -> (String, CLLocationDistance)? in
            let center = CLLocation(latitude: fence.latitude, longitude: fence.longitude)
            let distance = location.distance(from: center)
            return distance <= fence.radius ? (fence.name, distance) : nil
        }
        .sorted { $0.1 < $1.1 }
        .first?.0 ?? ""
    }
}

// MARK: - Widget snapshots

enum WidgetSnapshotUpdater {
    @MainActor
    static func refresh(entries: [FartEntry]) {
        let now = Date()
        let calendar = Calendar.current
        let day = entries.filter { CounterWindow.day.includes($0.eventDate, now: now, calendar: calendar) }.count
        let seven = entries.filter { CounterWindow.sevenDays.includes($0.eventDate, now: now, calendar: calendar) }.count
        let thirty = entries.filter { CounterWindow.thirtyDays.includes($0.eventDate, now: now, calendar: calendar) }.count
        let week = entries.filter { CounterWindow.currentWeek.includes($0.eventDate, now: now, calendar: calendar) }.count
        let score = entries.filter { CounterWindow.sevenDays.includes($0.eventDate, now: now, calendar: calendar) }
            .reduce(0) { $0 + $1.fartScore }
        RJFurzShared.writeCounts(day: day, sevenDays: seven, thirtyDays: thirty, currentWeek: week, all: entries.count, score: score)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Keychain

enum SecureStore {
    private static let service = "eu.rjuhas.furzapp.partner"

    static func set(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Partner backend DTOs

struct PartnerLoginResponse: Codable { let token: String; let username: String; let created: Bool? }

struct PartnerFriend: Codable, Identifiable, Hashable {
    var id: String { username }
    let username: String
    let status: String
    let battery: Int?
    let batteryState: String?
    let latitude: Double?
    let longitude: Double?
    let locationUpdatedAt: Date?
    let lastFartAt: Date?
    let todayCount: Int
    let sevenDayCount: Int
    let score7d: Int
}

struct PartnerFartDTO: Codable, Identifiable, Hashable {
    let id: String
    let owner: String
    let title: String
    let eventDate: Date
    let loudness: String
    let smellRating: Int
    let personalRating: Int
    let duration: Double
    let notes: String
    let context: String
    let address: String
    let geofence: String
    let latitude: Double?
    let longitude: Double?
    let hasAudio: Bool
    let comments: [PartnerComment]
}

struct PartnerComment: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let createdAt: Date
}

struct PartnerLeaderboardEntry: Codable, Identifiable, Hashable {
    var id: String { username }
    let username: String
    let count: Int
    let score: Int
    let averageSmell: Double
    let averageRating: Double
}

struct PartnerNudge: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    let message: String
    let createdAt: Date
    let status: String
    let delaySeconds: Int?
}

struct PartnerRefreshRequest: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    let createdAt: Date
    let status: String
}

struct PartnerFartUpload: Codable {
    let localID: String
    let title: String
    let eventDate: Date
    let loudness: String
    let smellRating: Int
    let personalRating: Int
    let duration: Double
    let notes: String
    let context: String
    let address: String
    let geofence: String
    let latitude: Double?
    let longitude: Double?
    let shareAudio: Bool
}

private struct TokenRequest: Codable { let username: String; let serverPassword: String }
private struct TokenResponse: Codable { let token: String; let username: String; let created: Bool? }
private struct PresencePayload: Codable {
    let latitude: Double?
    let longitude: Double?
    let battery: Int?
    let batteryState: String
    let shareLocation: Bool
    let shareBattery: Bool
    let lastFartAt: Date?
}
private struct NudgePayload: Codable { let message: String; let delaySeconds: Int }
private struct CommentPayload: Codable { let text: String }
private struct SimpleResponse: Codable { let ok: Bool }
private struct FartCreateResponse: Codable { let id: String }

// MARK: - Partner API

@MainActor
final class PartnerAPI: ObservableObject {
    static let shared = PartnerAPI()

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncAt: Date?

    static let enabledKey = "partner.enabled"
    static let baseURLKey = "partner.baseURL"
    static let usernameKey = "partner.username"
    static let shareLocationKey = "partner.shareLocation"
    static let shareBatteryKey = "partner.shareBattery"
    static let shareAudioKey = "partner.shareAudio"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        isConnected = SecureStore.get("token") != nil
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var baseURLString: String { UserDefaults.standard.string(forKey: Self.baseURLKey) ?? "" }
    var username: String { UserDefaults.standard.string(forKey: Self.usernameKey) ?? "" }
    var shareLocation: Bool { UserDefaults.standard.bool(forKey: Self.shareLocationKey) }
    var shareBattery: Bool { UserDefaults.standard.bool(forKey: Self.shareBatteryKey) }
    var shareAudio: Bool { UserDefaults.standard.bool(forKey: Self.shareAudioKey) }

    private var token: String? { SecureStore.get("token") }

    func ping() async throws -> Bool {
        let data = try await request(path: "/api/ping", method: "GET", authenticated: false)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["ok"] as? Bool == true
    }

    func registerOrLogin(register: Bool, username: String, password: String) async throws {
        let path = register ? "/api/account/register" : "/api/account/login"
        let payload = TokenRequest(username: username, serverPassword: password)
        let data = try await request(path: path, method: "POST", body: encoder.encode(payload), authenticated: false)
        let response = try decoder.decode(TokenResponse.self, from: data)
        UserDefaults.standard.set(response.username, forKey: Self.usernameKey)
        SecureStore.set(password, key: "serverPassword")
        SecureStore.set(response.token, key: "token")
        isConnected = true
        lastError = nil
    }

    func logout() {
        SecureStore.delete("token")
        isConnected = false
    }

    func deleteAccount() async throws {
        _ = try await request(path: "/api/account", method: "DELETE")
        SecureStore.delete("token")
        isConnected = false
    }

    func friends() async throws -> [PartnerFriend] {
        let data = try await request(path: "/api/friends", method: "GET")
        return try decoder.decode([PartnerFriend].self, from: data)
    }

    func friendRequests() async throws -> [String] {
        let data = try await request(path: "/api/friends/requests", method: "GET")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["incoming"] as? [String] ?? []
    }

    func sendFriendRequest(to username: String) async throws {
        _ = try await request(path: "/api/friends/request/\(escape(username))", method: "POST")
    }

    func acceptFriend(_ username: String) async throws {
        _ = try await request(path: "/api/friends/accept/\(escape(username))", method: "POST")
    }

    func declineFriend(_ username: String) async throws {
        _ = try await request(path: "/api/friends/decline/\(escape(username))", method: "POST")
    }

    func removeFriend(_ username: String) async throws {
        _ = try await request(path: "/api/friends/\(escape(username))", method: "DELETE")
    }

    func feed(days: Int = 7) async throws -> [PartnerFartDTO] {
        let data = try await request(path: "/api/feed?days=\(days)", method: "GET")
        return try decoder.decode([PartnerFartDTO].self, from: data)
    }

    func leaderboard(days: Int = 7) async throws -> [PartnerLeaderboardEntry] {
        let data = try await request(path: "/api/leaderboard?days=\(days)", method: "GET")
        return try decoder.decode([PartnerLeaderboardEntry].self, from: data)
    }

    func sendNudge(to username: String, message: String, delaySeconds: Int = 60) async throws {
        let payload = try encoder.encode(NudgePayload(message: message, delaySeconds: max(5, min(delaySeconds, 3600))))
        _ = try await request(path: "/api/nudges/\(escape(username))", method: "POST", body: payload)
    }

    func requestRefresh(friend username: String) async throws {
        _ = try await request(path: "/api/friends/\(escape(username))/refresh", method: "POST")
    }

    func refreshRequests() async throws -> [PartnerRefreshRequest] {
        let data = try await request(path: "/api/refresh-requests", method: "GET")
        return try decoder.decode([PartnerRefreshRequest].self, from: data)
    }

    func acknowledgeRefresh(id: String) async throws {
        _ = try await request(path: "/api/refresh-requests/\(escape(id))/ack", method: "POST")
    }

    func nudges() async throws -> [PartnerNudge] {
        let data = try await request(path: "/api/nudges", method: "GET")
        return try decoder.decode([PartnerNudge].self, from: data)
    }

    func respondToNudge(id: String, accept: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["accept": accept])
        _ = try await request(path: "/api/nudges/\(escape(id))/respond", method: "POST", body: body)
    }

    func comment(owner: String, fartID: String, text: String) async throws {
        let body = try encoder.encode(CommentPayload(text: text))
        _ = try await request(path: "/api/farts/\(escape(owner))/\(escape(fartID))/comments", method: "POST", body: body)
    }

    func syncPresence(location: CLLocation?, battery: Int?, lastFartAt: Date?) async {
        guard enabled, token != nil else { return }
        do {
            let payload = PresencePayload(
                latitude: shareLocation ? location?.coordinate.latitude : nil,
                longitude: shareLocation ? location?.coordinate.longitude : nil,
                battery: shareBattery ? battery : nil,
                batteryState: LocationService.shared.batteryStateText,
                shareLocation: shareLocation,
                shareBattery: shareBattery,
                lastFartAt: lastFartAt
            )
            _ = try await request(path: "/api/presence", method: "POST", body: encoder.encode(payload))
            lastSyncAt = .now
            isConnected = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            DebugLogger.shared.log("Partner-Presence Sync: \(error.localizedDescription)")
        }
    }

    func processRemoteCommands(lastFartAt: Date?) async {
        guard enabled, token != nil else { return }
        do {
            let refreshes = try await refreshRequests().filter { $0.status == "pending" }
            if !refreshes.isEmpty {
                LocationService.shared.requestCurrentLocation()
                try? await Task.sleep(for: .milliseconds(350))
                await syncPresence(location: LocationService.shared.location, battery: LocationService.shared.batteryPercent, lastFartAt: lastFartAt)
                for request in refreshes { try? await acknowledgeRefresh(id: request.id) }
            }

            let pending = try await nudges().filter { $0.status == "pending" }
            for nudge in pending {
                do {
                    try await FartAlarmKitService.schedulePartnerNudge(
                        title: "@\(nudge.from): \(nudge.message)",
                        after: TimeInterval(nudge.delaySeconds ?? 60)
                    )
                    try await respondToNudge(id: nudge.id, accept: true)
                    DebugLogger.shared.log("Furz-Anstupser automatisch als Alarm übernommen")
                } catch {
                    DebugLogger.shared.log("Remote-Alarm noch nicht möglich: \(error.localizedDescription)")
                }
            }
        } catch {
            DebugLogger.shared.log("Remote-Kommandos: \(error.localizedDescription)")
        }
    }

    func upload(entry: FartEntry) async {
        guard enabled, entry.isShared, token != nil else { return }
        do {
            let payload = PartnerFartUpload(
                localID: entry.id.uuidString,
                title: entry.title,
                eventDate: entry.eventDate,
                loudness: entry.loudnessRaw,
                smellRating: entry.smellRating,
                personalRating: entry.personalRating,
                duration: entry.duration,
                notes: entry.notes,
                context: entry.contextText,
                address: entry.resolvedAddress.isEmpty ? entry.locationText : entry.resolvedAddress,
                geofence: entry.geofenceName,
                latitude: shareLocation ? entry.latitude : nil,
                longitude: shareLocation ? entry.longitude : nil,
                shareAudio: shareAudio && entry.audioFilename != nil
            )
            let data = try await request(path: "/api/farts", method: "POST", body: encoder.encode(payload))
            let created = try decoder.decode(FartCreateResponse.self, from: data)
            entry.remoteID = created.id

            if shareAudio, let filename = entry.audioFilename {
                let audio = try Data(contentsOf: AudioFileStore.url(for: filename))
                _ = try await request(path: "/api/farts/\(escape(created.id))/audio", method: "PUT", body: audio, contentType: "application/octet-stream")
            }
            isConnected = true
            lastSyncAt = .now
        } catch {
            lastError = error.localizedDescription
            DebugLogger.shared.log("Furz-Upload fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    func downloadAudio(owner: String, fartID: String) async throws -> URL {
        let data = try await request(path: "/api/farts/\(escape(owner))/\(escape(fartID))/audio", method: "GET")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("partner-\(UUID().uuidString).m4a")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func request(path: String, method: String, body: Data? = nil, authenticated: Bool = true, contentType: String = "application/json") async throws -> Data {
        guard let base = normalizedBaseURL(), let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw NSError(domain: "RJFurzPartner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend-Adresse ist ungültig."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let token else {
                throw NSError(domain: "RJFurzPartner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nicht am Furz-Backend angemeldet."])
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw NSError(domain: "RJFurzPartner", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message ?? "Backend-Fehler HTTP \(http.statusCode)"])
        }
        return data
    }

    private func normalizedBaseURL() -> URL? {
        var value = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if !value.contains("://") {
            let host = value.split(separator: ":", maxSplits: 1).first.map(String.init) ?? value
            let looksLikeIPv4 = host.split(separator: ".").count == 4 && host.split(separator: ".").allSatisfy { Int($0) != nil }
            let isLocal = host == "localhost" || host.hasSuffix(".local") || looksLikeIPv4
            value = (isLocal ? "http://" : "https://") + value
        }
        if !value.hasSuffix("/") { value += "/" }
        return URL(string: value)
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}


// MARK: - Background partner sync bridge

@MainActor
final class PartnerPresenceCoordinator: ObservableObject {
    static let shared = PartnerPresenceCoordinator()
    private var lastFartAt: Date?

    private init() {
        LocationService.shared.onBackgroundLocation = { location in
            Task { @MainActor in
                await PartnerAPI.shared.syncPresence(
                    location: location,
                    battery: LocationService.shared.batteryPercent,
                    lastFartAt: self.lastFartAt
                )
                await PartnerAPI.shared.processRemoteCommands(lastFartAt: self.lastFartAt)
            }
        }
    }

    func configure(entries: [FartEntry]) {
        lastFartAt = entries.map(\.eventDate).max()
        let enabled = UserDefaults.standard.bool(forKey: PartnerAPI.enabledKey)
        let shareLocation = UserDefaults.standard.bool(forKey: PartnerAPI.shareLocationKey)
        LocationService.shared.setBackgroundSharing(enabled && shareLocation)
        Task {
            await PartnerAPI.shared.syncPresence(
                location: LocationService.shared.location,
                battery: LocationService.shared.batteryPercent,
                lastFartAt: lastFartAt
            )
            await PartnerAPI.shared.processRemoteCommands(lastFartAt: lastFartAt)
        }
    }
}
