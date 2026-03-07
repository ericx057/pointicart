import UserNotifications

enum NotificationService {

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func scheduleAbandonedCartReminder(
        storeName: String,
        productName: String,
        cartItemIds: String,
        delayMinutes: Int = 120
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Still thinking about it?"
        content.body = "Still thinking about the \(productName)? Tap to finish your checkout at \(storeName)."
        content.sound = .default
        content.userInfo = [
            "deepLink": "pointwise.shop/checkout?items=\(cartItemIds)"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(delayMinutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "abandoned-cart",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    static func cancelAbandonedCartReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["abandoned-cart"])
    }
}
