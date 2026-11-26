import Foundation
import UserNotifications
import SubspaceCore

enum ReminderService {
    static func requestAuthorization() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
    static func reschedule(records: [SubscriptionRecord], enabled: Bool) async throws -> String? {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return nil }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return "Renewal reminders need notification permission in iOS Settings." }
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .year, value: 2, to: .now) else { return nil }
        var reminders: [(Payment, Date)] = []
        for record in records {
            guard let days = record.reminderDays else { continue }
            for payment in RecurrenceEngine().payments(record, in: DateInterval(start: calendar.startOfDay(for: .now), end: end)) {
                guard let day = calendar.date(byAdding: .day, value: -days, to: payment.date), let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > .now else { continue }
                reminders.append((payment, fire))
            }
        }
        let scheduled = reminders.sorted { $0.1 < $1.1 }.prefix(60)
        for (payment, fire) in scheduled {
            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = "\(payment.subscription.name) renews soon"
            content.body = "\(Money.format(payment.subscription.amount, currency: payment.subscription.currency)) on \(payment.date.formatted(date: .abbreviated, time: .omitted))."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            try await center.add(UNNotificationRequest(identifier: payment.id, content: content, trigger: trigger))
        }
        return "\(scheduled.count) reminders scheduled. iOS allows a limited queue; opening Subvelle refreshes the next 60 reminders. Delivery depends on your device’s notification settings."
    }
}
