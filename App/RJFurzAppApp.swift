import SwiftUI
import SwiftData

@main
struct RJFurzAppApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                FartEntry.self,
                FartFolder.self,
                FartReminder.self,
                FartGeofence.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
            DebugLogger.shared.log("App gestartet – SwiftData bereit")
        } catch {
            fatalError("SwiftData konnte nicht initialisiert werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(container)
    }
}
