import Foundation
import UserNotifications

extension NotificationManager {
    func scheduleInactivity(_ reminder: FartReminder, lastFartDate: Date?) async throws {
        let center = UNUserNotificationCenter.current()
        await removeInactivity(reminderID: reminder.id)
        guard reminder.isEnabled, reminder.mode == .inactivity else { return }
        _ = await requestAuthorization()

        let base = lastFartDate ?? Date()
        var target = base.addingTimeInterval(Double(max(1, reminder.inactivityHours)) * 3600)
        if target <= Date() { target = Date().addingTimeInterval(60) }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Schon länger nichts eingetragen 💨 Schon gefurzt – oder herrscht ungewöhnliche Windstille?"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, target.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(
            identifier: "eu.rjuhas.furzapp.inactivity.\(reminder.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
        DebugLogger.shared.log("Inaktivitäts-Furzwecker geplant: \(reminder.inactivityHours) h")
    }

    func removeInactivity(reminderID: UUID) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["eu.rjuhas.furzapp.inactivity.\(reminderID.uuidString)"]
        )
    }

    func refreshInactivity(reminders: [FartReminder], entries: [FartEntry]) async {
        let last = entries.map(\.eventDate).max()
        for reminder in reminders where reminder.mode == .inactivity {
            try? await scheduleInactivity(reminder, lastFartDate: last)
        }
    }
}
