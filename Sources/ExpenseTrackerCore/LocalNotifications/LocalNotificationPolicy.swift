import Foundation

public enum LocalNotificationKind: String, Equatable, Sendable {
    case gmailSyncFinished
    case reviewReminder
}

public struct LocalNotificationRequest: Equatable, Sendable {
    public let kind: LocalNotificationKind
    public let identifier: String
    public let title: String
    public let body: String
    public let scheduledAt: Date?

    public init(
        kind: LocalNotificationKind,
        identifier: String,
        title: String,
        body: String,
        scheduledAt: Date? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.body = body
        self.scheduledAt = scheduledAt
    }
}

public enum LocalNotificationDecision: Equatable, Sendable {
    case schedule(LocalNotificationRequest)
    case cancel(identifier: String)

    public var request: LocalNotificationRequest? {
        guard case let .schedule(request) = self else {
            return nil
        }
        return request
    }
}

public enum LocalNotificationPolicy {
    public static let gmailSyncFinishedIdentifier = "gmail-sync-finished"
    public static let reviewReminderIdentifier = "pending-review-reminder"

    public static func syncCompletion(
        candidateCount: Int,
        skippedMessageCount: Int
    ) -> LocalNotificationRequest {
        var body = "\(candidateCount) eligible \(candidateCount == 1 ? "email is" : "emails are") ready to import."
        if skippedMessageCount > 0 {
            body += " Gmail skipped \(skippedMessageCount) labeled \(skippedMessageCount == 1 ? "message" : "messages")."
        }
        return LocalNotificationRequest(
            kind: .gmailSyncFinished,
            identifier: gmailSyncFinishedIdentifier,
            title: "Gmail sync finished",
            body: body
        )
    }

    public static func reviewReminder(
        pendingReviewCount: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> LocalNotificationDecision {
        guard pendingReviewCount > 0 else {
            return .cancel(identifier: reviewReminderIdentifier)
        }

        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let scheduledAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? nextDay
        let body = "\(pendingReviewCount) \(pendingReviewCount == 1 ? "transaction is" : "transactions are") waiting for your review."

        return .schedule(
            LocalNotificationRequest(
                kind: .reviewReminder,
                identifier: reviewReminderIdentifier,
                title: "Transactions need review",
                body: body,
                scheduledAt: scheduledAt
            )
        )
    }
}
