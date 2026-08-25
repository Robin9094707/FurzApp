import Foundation
import SwiftUI
import AlarmKit

struct FartAlarmMetadata: AlarmMetadata {
    let title: String
}

enum FartAlarmKitService {
    static func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await AlarmManager.shared.requestAuthorization()
    }

    static func schedule(reminder: FartReminder) async throws {
        guard reminder.isEnabled, reminder.mode == .clock else {
            try? AlarmManager.shared.cancel(id: reminder.id)
            return
        }

        let authorization = AlarmManager.shared.authorizationState
        if authorization == .notDetermined {
            _ = try await requestAuthorization()
        }

        try? AlarmManager.shared.cancel(id: reminder.id)

        let stopButton = AlarmButton(
            text: "Fertig",
            textColor: .white,
            systemImageName: "checkmark.circle.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: reminder.title,
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: FartAlarmMetadata(title: reminder.title),
            tintColor: Color.purple
        )

        let time = Alarm.Schedule.Relative.Time(hour: reminder.hour, minute: reminder.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence
        if reminder.weekdaysMask == 0 {
            recurrence = .weekly([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
        } else {
            recurrence = .weekly(weekdays(for: reminder))
        }
        let relative = Alarm.Schedule.Relative(time: time, repeats: recurrence)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .relative(relative),
            attributes: attributes
        )
        _ = try await AlarmManager.shared.schedule(id: reminder.id, configuration: configuration)
        DebugLogger.shared.log("AlarmKit-Furzwecker geplant: \(reminder.title)")
    }

    static func schedulePartnerNudge(title: String, after seconds: TimeInterval = 60) async throws {
        let id = UUID()
        let stopButton = AlarmButton(text: "Okay 💨", textColor: .white, systemImageName: "wind")
        let alert = AlarmPresentation.Alert(title: title, stopButton: stopButton)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: FartAlarmMetadata(title: title),
            tintColor: Color.orange
        )
        let schedule = Alarm.Schedule.fixed(Date().addingTimeInterval(max(5, seconds)))
        let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: schedule, attributes: attributes)
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try await requestAuthorization()
        }
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func cancel(reminderID: UUID) {
        try? AlarmManager.shared.cancel(id: reminderID)
    }

    private static func weekdays(for reminder: FartReminder) -> [Locale.Weekday] {
        var values: [Locale.Weekday] = []
        if reminder.includes(weekday: 1) { values.append(.sunday) }
        if reminder.includes(weekday: 2) { values.append(.monday) }
        if reminder.includes(weekday: 3) { values.append(.tuesday) }
        if reminder.includes(weekday: 4) { values.append(.wednesday) }
        if reminder.includes(weekday: 5) { values.append(.thursday) }
        if reminder.includes(weekday: 6) { values.append(.friday) }
        if reminder.includes(weekday: 7) { values.append(.saturday) }
        return values.isEmpty ? [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday] : values
    }
}
