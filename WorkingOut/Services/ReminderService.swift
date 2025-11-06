import Foundation
import UserNotifications

enum ReminderService {
    private static let weightReminderID = "weekly_weight_reminder"
    private static let weekdayKey = "reminderWeekday"
    private static let hourKey = "reminderHour"
    private static let minuteKey = "reminderMinute"

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

    static func scheduleIfEnabled() {
        let enabled = UserDefaults.standard.bool(forKey: "enableWeeklyWeightReminder")
        if enabled {
            requestAuthorization { ok in
                if ok {
                    let d = UserDefaults.standard
                    let weekday = d.integer(forKey: weekdayKey) == 0 ? 2 : d.integer(forKey: weekdayKey)
                    let hour = d.object(forKey: hourKey) as? Int ?? 9
                    let minute = d.object(forKey: minuteKey) as? Int ?? 0
                    scheduleWeeklyWeightReminder(weekday: weekday, hour: hour, minute: minute)
                }
            }
        } else {
            cancelWeeklyWeightReminder()
        }
    }
}
