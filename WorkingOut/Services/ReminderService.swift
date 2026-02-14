import Foundation
import UserNotifications

enum ReminderService {
    private static let weightReminderID = "weekly_weight_reminder"
    private static let weekdayKey = "reminderWeekday"
    private static let hourKey = "reminderHour"
    private static let minuteKey = "reminderMinute"
    private static let runningPlanPrefix = "running_plan_"

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .denied:
                completion(false)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    completion(granted)
                }
            @unknown default:
                completion(false)
            }
        }
    }

    static func scheduleWeeklyWeightReminder(weekday: Int = 2, hour: Int = 9, minute: Int = 0) { // default Monday 9:00
        let content = UNMutableNotificationContent()
        content.title = "Update Your Weight"
        content.body = "Take 30 seconds to log your current weight."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: weightReminderID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { print("Reminder schedule error: \(error.localizedDescription)") }
        }
        // Persist chosen schedule
        let d = UserDefaults.standard
        d.set(weekday, forKey: weekdayKey)
        d.set(hour, forKey: hourKey)
        d.set(minute, forKey: minuteKey)
    }

    static func cancelWeeklyWeightReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weightReminderID])
    }

    static func scheduleRunningPlanReminders(planID: UUID, weekdays: [Int], hour: Int, minute: Int, title: String) {
        let cleanedWeekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        guard !cleanedWeekdays.isEmpty else {
            cancelRunningPlanReminders(planID: planID)
            return
        }

        requestAuthorization { ok in
            guard ok else { return }

            cancelRunningPlanReminders(planID: planID)

            let center = UNUserNotificationCenter.current()
            for weekday in cleanedWeekdays {
                let content = UNMutableNotificationContent()
                content.title = "Running Assistant"
                content.body = "\(title): planned run today."
                content.sound = .default

                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hour
                comps.minute = minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let identifier = runningPlanIdentifier(planID: planID, weekday: weekday)
                let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(req) { error in
                    if let error {
                        print("Running plan reminder error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    static func cancelRunningPlanReminders(planID: UUID) {
        let identifiers = (1...7).map { runningPlanIdentifier(planID: planID, weekday: $0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func scheduleIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "enableWeeklyWeightReminder")
        if enabled {
            requestAuthorization { ok in
                if ok {
                    let d = UserDefaults.standard
                    // Use stored values, or defaults if not set
                    // Note: We use object(forKey:) to distinguish between "not set" and "set to 0"
                    let weekday = d.object(forKey: weekdayKey) as? Int ?? 2  // Default: Monday
                    let hour = d.object(forKey: hourKey) as? Int ?? 9        // Default: 9 AM
                    let minute = d.object(forKey: minuteKey) as? Int ?? 0    // Default: 0 minutes
                    scheduleWeeklyWeightReminder(weekday: weekday, hour: hour, minute: minute)
                }
            }
        } else {
            cancelWeeklyWeightReminder()
        }
    }

    private static func runningPlanIdentifier(planID: UUID, weekday: Int) -> String {
        "\(runningPlanPrefix)\(planID.uuidString)_\(weekday)"
    }
}
