import Foundation
import SwiftData
@preconcurrency import UserNotifications

@MainActor
protocol LocalNotificationScheduling: AnyObject {
    func requestAuthorizationIfNeeded() async
    func schedule(_ request: LocalNotificationRequest) async
    func cancel(identifier: String)
}

@MainActor
final class LocalNotificationScheduler: LocalNotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(_ request: LocalNotificationRequest) async {
        let settings = await center.notificationSettings()
        guard canDeliverNotifications(with: settings.authorizationStatus) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["notificationKind": request.kind.rawValue]

        let trigger = request.scheduledAt.map { scheduledAt in
            let components = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: scheduledAt)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let notification = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(notification)
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func reconcileReviewReminder(in modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.status == "needsReview" }
        )
        let pendingReviewCount = (try? modelContext.fetchCount(descriptor)) ?? 0

        switch LocalNotificationPolicy.reviewReminder(pendingReviewCount: pendingReviewCount, now: .now) {
        case .schedule(let request):
            await schedule(request)
        case .cancel(let identifier):
            cancel(identifier: identifier)
        }
    }

    private func canDeliverNotifications(with status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}
