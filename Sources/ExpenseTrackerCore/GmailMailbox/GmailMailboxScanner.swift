import Foundation

public struct GmailLabel: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct GmailMessagePage: Equatable, Sendable {
    public let messageIDs: [String]
    public let nextPageToken: String?

    public init(messageIDs: [String], nextPageToken: String?) {
        self.messageIDs = messageIDs
        self.nextPageToken = nextPageToken
    }
}

public enum GmailMailboxFailure: Error, Equatable, Sendable {
    case transactionLabelNotFound
    case duplicateTransactionLabels
    case authorizationExpired
    case unavailable
    case malformedResponse
}

public protocol GmailMailboxClient: Sendable {
    func listLabels() async throws(GmailMailboxFailure) -> [GmailLabel]
    func messagePage(
        in labelID: String,
        after startDate: Date,
        pageToken: String?
    ) async throws(GmailMailboxFailure) -> GmailMessagePage
    func message(id: String) async throws(GmailMailboxFailure) -> BankEmail
}

public struct GmailMailboxScanResult: Sendable {
    public let candidates: [BankEmail]
    public let excludedFlipMessageCount: Int

    public init(candidates: [BankEmail], excludedFlipMessageCount: Int) {
        self.candidates = candidates
        self.excludedFlipMessageCount = excludedFlipMessageCount
    }
}

public struct GmailMailboxScanner: Sendable {
    private let client: any GmailMailboxClient
    private let calendar: Calendar

    public init(client: any GmailMailboxClient, calendar: Calendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    public func scan(now: Date) async throws(GmailMailboxFailure) -> GmailMailboxScanResult {
        let labels = try await client.listLabels()
        let matchingLabels = labels.filter { $0.name == "Transaction" }

        guard matchingLabels.count == 1, let label = matchingLabels.first else {
            throw matchingLabels.isEmpty ? .transactionLabelNotFound : .duplicateTransactionLabels
        }
        guard let startDate = calendar.date(byAdding: .day, value: -90, to: now) else {
            throw .malformedResponse
        }

        var pageToken: String?
        var seenPageTokens = Set<String>()
        var seenMessageIDs = Set<String>()
        var candidates = [BankEmail]()
        var excludedFlipMessageCount = 0

        while true {
            let page = try await client.messagePage(
                in: label.id,
                after: startDate,
                pageToken: pageToken
            )

            for messageID in page.messageIDs where seenMessageIDs.insert(messageID).inserted {
                let email = try await client.message(id: messageID)
                guard email.messageID == messageID else {
                    throw .malformedResponse
                }
                guard email.receivedAt >= startDate else { continue }

                if GmailMailboxFilter.isFlipReceipt(email) {
                    excludedFlipMessageCount += 1
                } else {
                    candidates.append(email)
                }
            }

            guard let nextPageToken = page.nextPageToken else { break }
            guard seenPageTokens.insert(nextPageToken).inserted else {
                throw .malformedResponse
            }
            pageToken = nextPageToken
        }

        return GmailMailboxScanResult(
            candidates: candidates,
            excludedFlipMessageCount: excludedFlipMessageCount
        )
    }
}

public enum GmailMailboxFilter {
    public static func isFlipReceipt(_ email: BankEmail) -> Bool {
        let body = email.body.lowercased()
        return body.contains("your transaction has been successfully processed")
            && body.contains("destination bank")
            && body.contains("destination account number")
    }
}
