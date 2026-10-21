import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

@MainActor
@Observable
final class LocalNotificationRoute {
    static let shared = LocalNotificationRoute()

    var destination: LocalNotificationKind?

    private init() {}

    func open(kindRawValue: String?) {
        guard let kindRawValue,
              let kind = LocalNotificationKind(rawValue: kindRawValue) else {
            return
        }
        destination = kind
    }

    func clearDestination() {
        destination = nil
    }
}

final class LocalNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kindRawValue = response.notification.request.content.userInfo["notificationKind"] as? String
        Task { @MainActor in
            LocalNotificationRoute.shared.open(kindRawValue: kindRawValue)
        }
        completionHandler()
    }
}
