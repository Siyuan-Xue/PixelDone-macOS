import Foundation
@preconcurrency import UserNotifications

@MainActor
final class PixelDoneNotificationDelegate:
    NSObject,
    UNUserNotificationCenterDelegate {
    private let store: PixelDoneStore

    init(store: PixelDoneStore) {
        self.store = store
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier
                == PixelDoneNotificationService.snoozeActionIdentifier,
              let todoID = response.notification.request.content
                .userInfo["todo_id"] as? String else {
            return
        }
        await store.snoozeNotification(todoID: todoID)
    }
}
