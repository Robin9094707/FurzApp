import SwiftUI
import SwiftData
import MapKit
import CoreLocation

private struct HeatPoint: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let score: Int
}

struct FartHeatmapView: View {
    @Query(sort: \FartEntry.eventDate, order: .reverse) private var entries: [FartEntry]
    @State private var period: CounterWindow = .sevenDays
    @State private var position: MapCameraPosition = .automatic

    private var filtered: [FartEntry] {
        entries.filter { $0.coordinate != nil && period.includes($0.eventDate) }
    }

    private var heatPoints: [HeatPoint] {
        var buckets: [String: (lat: Double, lon: Double, count: Int, score: Int)] = [:]
        for entry in filtered {
            guard let lat = entry.latitude, let lon = entry.longitude else { continue }
            // ~100-m-Raster für eine einfache lokale Heatmap ohne Drittanbieter-SDK.
            let latKey = Int((lat * 1000).rounded())
            let lonKey = Int((lon * 1000).rounded())
            let key = "\(latKey):\(lonKey)"
            var value = buckets[key] ?? (0, 0, 0, 0)
            value.lat += lat
            value.lon += lon
            value.count += 1
            value.score += entry.fartScore
            buckets[key] = value
        }
        return buckets.map { key, value in
            HeatPoint(
                id: key,
                coordinate: CLLocationCoordinate2D(
                    latitude: value.lat / Double(value.count),
                    longitude: value.lon / Double(value.count)
                ),
                count: value.count,
                score: value.score
            )
        }
    }

    var body: some View {
        ZStack {
            RJBackground()
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Furz-Heatmap 💨🗺️").font(.title2.bold())
                            Picker("Zeitraum", selection: $period) {
                                ForEach(CounterWindow.allCases) { value in
                                    Text(value.rawValue).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            HStack {
                                MetricPill(icon: "mappin.and.ellipse", value: "\(filtered.count)", label: "mit Ort")
                                MetricPill(icon: "flame.fill", value: "\(filtered.reduce(0) { $0 + $1.fartScore })", label: "Score")
                            }
                        }
                    }

                    Map(position: $position) {
                        ForEach(heatPoints) { point in
                            Annotation("\(point.count) Fürze", coordinate: point.coordinate) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(min(0.75, 0.22 + Double(point.count) * 0.08)))
                                        .frame(width: min(84, 34 + CGFloat(point.count * 6)), height: min(84, 34 + CGFloat(point.count * 6)))
                                    Text("\(point.count)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                                .shadow(radius: 3)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .frame(height: 390)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12))
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView(
                            "Noch keine Furz-Orte",
                            systemImage: "map",
                            description: Text("Aktiviere die optionale Standorterfassung oder füge bei einem Furz einen Standort hinzu.")
                        )
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Top-Orte").font(.headline)
                                ForEach(topLocationNames, id: \.name) { item in
                                    HStack {
                                        Label(item.name, systemImage: "mappin.circle.fill")
                                        Spacer()
                                        Text("\(item.count)×").bold().monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Karte & Heatmap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var topLocationNames: [(name: String, count: Int)] {
        let names = filtered.map {
            if !$0.geofenceName.isEmpty { return $0.geofenceName }
            if !$0.resolvedAddress.isEmpty { return $0.resolvedAddress }
            return $0.locationText.isEmpty ? "Unbenannter Ort" : $0.locationText
        }
        return Dictionary(grouping: names, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0 }
    }
}

struct FartLocationCard: View {
    let entry: FartEntry
    @State private var position: MapCameraPosition

    init(entry: FartEntry) {
        self.entry = entry
        if let coordinate = entry.coordinate {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        if let coordinate = entry.coordinate {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hier ist er passiert").font(.headline)
                    Map(position: $position) {
                        Marker(entry.geofenceName.isEmpty ? entry.title : entry.geofenceName, systemImage: "wind", coordinate: coordinate)
                    }
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if !entry.resolvedAddress.isEmpty {
                        Label(entry.resolvedAddress, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct GeofenceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FartGeofence.name) private var geofences: [FartGeofence]
    @Query private var entries: [FartEntry]
    @State private var showAdd = false
    @State private var pendingDelete: FartGeofence?

    var body: some View {
        List {
            Section {
                if geofences.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Furz-Orte",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Lege Zuhause, Arbeit oder Lieblingsort an. Beim Speichern erkennt die App automatisch, ob dein Furz in diesem Radius lag.")
                    )
                } else {
                    ForEach(geofences) { fence in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(fence.name, systemImage: fence.symbol)
                                Spacer()
                                Text("\(Int(fence.radius)) m")
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(entries.filter { $0.geofenceName == fence.name }.count) Fürze zugeordnet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDelete = fence } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                Text("Die Geofences dienen zur lokalen Einordnung deiner Furz-Orte. Die Koordinaten verlassen dein Gerät nur, wenn du Furzfreunde und Standortfreigabe separat aktivierst.")
            }
        }
        .navigationTitle("Furz-Orte / Geofences")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { GeofenceEditorView() }
        .alert("Furz-Ort löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let fence = pendingDelete {
                    modelContext.delete(fence)
                    try? modelContext.save()
                }
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Bereits gespeicherte Fürze behalten ihren bisherigen Ortsnamen.")
        }
    }
}

private struct GeofenceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationService = LocationService.shared
    @State private var name = "Zuhause"
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var radius = 120.0
    @State private var symbol = "house.fill"
    @State private var address = ""
    @State private var isLocating = false

    private let symbols = ["house.fill", "briefcase.fill", "heart.fill", "star.fill", "fork.knife", "figure.walk", "car.fill", "mappin.circle.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Furz-Ort") {
                    TextField("Name", text: $name)
                    Picker("Symbol", selection: $symbol) {
                        ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                    Button { Task { await useCurrentLocation() } } label: {
                        Label(isLocating ? "Ermittle Standort …" : "Aktuellen Standort verwenden", systemImage: "location.fill")
                    }
                    .disabled(isLocating)
                    if !address.isEmpty { Text(address).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("Radius") {
                    Slider(value: $radius, in: 30...2000, step: 10)
                    LabeledContent("Radius", value: "\(Int(radius)) m")
                    TextField("Breitengrad", value: $latitude, format: .number.precision(.fractionLength(6)))
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Längengrad", value: $longitude, format: .number.precision(.fractionLength(6)))
                        .keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle("Neuer Furz-Ort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        modelContext.insert(FartGeofence(name: name, latitude: latitude, longitude: longitude, radius: radius, symbol: symbol))
                        try? modelContext.save()
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (latitude == 0 && longitude == 0))
                }
            }
        }
    }

    @MainActor
    private func useCurrentLocation() async {
        isLocating = true
        locationService.requestCurrentLocation()
        for _ in 0..<12 {
            if let location = locationService.location,
               Date().timeIntervalSince(location.timestamp) < 90 {
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
                address = await AddressResolver.reverse(location)
                isLocating = false
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        isLocating = false
    }
}
