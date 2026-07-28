import Foundation
import PixelDoneDomain
import UserNotifications

enum NotificationAuthorizationState: Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

actor PixelDoneNotificationService {
    static let categoryIdentifier = "PIXELDONE_TODO_DUE"
    static let stopActionIdentifier = "PIXELDONE_STOP"
    static let snoozeActionIdentifier = "PIXELDONE_SNOOZE_10"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func configureCategories() {
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: Self.snoozeActionIdentifier,
                        title: "Snooze 10 min"
                    ),
                    UNNotificationAction(
                        identifier: Self.stopActionIdentifier,
                        title: "Stop",
                        options: [.destructive]
                    ),
                ],
                intentIdentifiers: []
            ),
        ])
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(
            options: [.alert, .badge, .sound, .provisional]
        )
    }

    func authorizationState() async -> NotificationAuthorizationState {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .provisional: .provisional
        case .authorized, .ephemeral: .authorized
        @unknown default: .notDetermined
        }
    }

    func synchronize(todos: [PixelDoneTodo]) async {
        center.removePendingNotificationRequests(
            withIdentifiers: todos.map { "todo:\($0.id)" }
        )
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        for todo in todos
            where !todo.completed
                && todo.trashedAtMillis == nil
                && todo.dueAtMillis > now {
            let content = UNMutableNotificationContent()
            content.title = todo.priority == .xHigh
                ? "XHIGH task due"
                : "Task due"
            content.body = todo.title
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["todo_id": todo.id]
            content.interruptionLevel =
                todo.priority == .xHigh ? .timeSensitive : .active
            let due = Date(
                timeIntervalSince1970: Double(todo.dueAtMillis) / 1_000
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: due
                ),
                repeats: false
            )
            try? await center.add(
                UNNotificationRequest(
                    identifier: "todo:\(todo.id)",
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    func snooze(todo: PixelDoneTodo, minutes: Int = 10) async throws {
        let content = UNMutableNotificationContent()
        content.title = todo.priority == .xHigh
            ? "XHIGH task due"
            : "Task due"
        content.body = todo.title
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["todo_id": todo.id]
        content.interruptionLevel =
            todo.priority == .xHigh ? .timeSensitive : .active
        try await center.add(
            UNNotificationRequest(
                identifier: "todo:\(todo.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(minutes * 60),
                    repeats: false
                )
            )
        )
    }
}
