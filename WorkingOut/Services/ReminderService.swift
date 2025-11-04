import Foundation
import UserNotifications

enum ReminderService {
    private static let weightReminderID = "weekly_weight_reminder"

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
    }

    static func cancelWeeklyWeightReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weightReminderID])
    }

    static func scheduleIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "enableWeeklyWeightReminder")
        if enabled {
            requestAuthorization { ok in
                if ok { scheduleWeeklyWeightReminder() }
            }
        } else {
            cancelWeeklyWeightReminder()
        }
    }
}

