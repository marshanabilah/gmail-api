import Foundation

public struct BankEmail: Sendable {
    public let messageID: String
    public let sender: String
    public let subject: String
    public let body: String
    public let receivedAt: Date

    public init(messageID: String, sender: String, subject: String, body: String, receivedAt: Date) {
        self.messageID = messageID
        self.sender = sender
        self.subject = subject
        self.body = body
        self.receivedAt = receivedAt
    }
}

public struct JagoDebitCardEmailParser: BankEmailParsing {
    public init() {}

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        let normalizedBody = email.body.lowercased()
        guard normalizedBody.contains("using your jago debit card") else { return .unsupported }
        guard let amount = rupiahAmount(in: email.body) else { return .unsupported }

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "jago",
            occurredAt: email.receivedAt,
            merchant: "Jago debit card transaction",
            amount: amount,
            kind: .cardPurchase,
            confidence: 0.55
        ))
    }

    private func rupiahAmount(in body: String) -> Decimal? {
        guard let match = body.range(of: #"Rp\s*([0-9.,]+)"#, options: .regularExpression) else { return nil }
        let numeric = body[match]
            .replacingOccurrences(of: "Rp", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX"))
    }
}

public struct OCTOCIMBEmailParser: BankEmailParsing {
    private let dateFormatter: DateFormatter

    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "dd MMMM yyyy HH:mm:ss"
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        guard email.body.localizedCaseInsensitiveContains("OCTO App transaction") else { return .unsupported }
        guard field("Status", in: email.body)?.caseInsensitiveCompare("SUCCESS") == .orderedSame else { return .ignored }
        guard
            let occurredAt = dateFormatter.date(from: field("Date/Time", in: email.body) ?? ""),
            let transactionType = field("Transaction Type", in: email.body),
            let amount = rupiahAmount(from: field("Transfer Amount", in: email.body) ?? "")
        else {
            return .unsupported
        }

        guard transactionType.localizedCaseInsensitiveContains("Transfer") else { return .unsupported }
        let kind: TransactionKind = transactionType.localizedCaseInsensitiveContains("to Own") ? .transferOut : .unknown

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "octoCimb",
            occurredAt: occurredAt,
            merchant: transactionType,
            amount: amount,
            kind: kind,
            confidence: kind == .transferOut ? 0.99 : 0.7
        ))
    }

    private func field(_ label: String, in body: String) -> String? {
        let pattern = "\\Q\(label)\\E\\s*:\\s*(?:\\n\\s*)?([^\\n]+)"
        guard let range = body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(body[range])
        guard let separator = match.firstIndex(of: ":") else { return nil }
        return String(match[match.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rupiahAmount(from value: String) -> Decimal? {
        let numeric = value
            .uppercased()
            .replacingOccurrences(of: "IDR", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX"))
    }
}

public struct MandiriTransferEmailParser: BankEmailParsing {
    private let dateFormatter: DateFormatter

    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "d MMM yyyy HH:mm:ss"
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        guard email.body.localizedCaseInsensitiveContains("Transfer Successful") else { return .unsupported }
        guard
            let date = field("Date", in: email.body),
            let time = field("Time", in: email.body),
            let occurredAt = dateFormatter.date(from: "\(date) \(time.replacingOccurrences(of: " WIB", with: ""))"),
            let recipient = recipient(in: email.body),
            let amount = rupiahAmount(from: field("Transfer Amount", in: email.body) ?? "")
        else {
            return .unsupported
        }

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "mandiri",
            occurredAt: occurredAt,
            merchant: recipient,
            amount: amount,
            kind: .transferOut,
            confidence: 0.75
        ))
    }

    private func field(_ label: String, in body: String) -> String? {
        let lines = body.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (index, line) in lines.enumerated() {
            let cells = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.count == 2, cells[0].caseInsensitiveCompare(label) == .orderedSame {
                return cells[1]
            }

            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, parts[0].caseInsensitiveCompare(label) == .orderedSame {
                return parts[1]
            }

            if line.caseInsensitiveCompare(label) == .orderedSame, lines.indices.contains(index + 1) {
                return lines[index + 1]
            }
        }
        return nil
    }

    private func recipient(in body: String) -> String? {
        let lines = body.split(whereSeparator: \.isNewline).map { line in
            line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespaces)
        }
        guard let recipientIndex = lines.firstIndex(where: { $0.caseInsensitiveCompare("Recipient") == .orderedSame }) else {
            return nil
        }
        return lines.dropFirst(recipientIndex + 1).first { line in
            !line.isEmpty && !line.localizedCaseInsensitiveContains("Bank Mandiri")
        }
    }

    private func rupiahAmount(from value: String) -> Decimal? {
        let numeric = value
            .uppercased()
            .replacingOccurrences(of: "RP", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX"))
    }
}

public enum BankEmailParseResult: Equatable, Sendable {
    case transaction(TransactionDraft)
    case ignored
    case unsupported
}

public protocol BankEmailParsing: Sendable {
    func parse(_ email: BankEmail) -> BankEmailParseResult
}

public struct BCAEmailParser: BankEmailParsing {
    private let dateFormatter: DateFormatter

    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss"
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        let fields = tableFields(in: email.body)
        guard !fields.isEmpty else { return .unsupported }
        guard fields["Status"]?.caseInsensitiveCompare("Successful") == .orderedSame else { return .ignored }
        guard fields["Transaction Type"]?.caseInsensitiveCompare("QRIS Payment") == .orderedSame else { return .unsupported }
        guard
            let occurredAt = dateFormatter.date(from: fields["Transaction Date"] ?? ""),
            let merchant = fields["Payment to"], !merchant.isEmpty,
            let amount = rupiahAmount(from: fields["Total Payment"] ?? "")
        else {
            return .unsupported
        }

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "bca",
            occurredAt: occurredAt,
            merchant: merchant,
            amount: amount,
            kind: .qrisPayment,
            confidence: 0.99
        ))
    }

    private func tableFields(in body: String) -> [String: String] {
        body
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { fields, line in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !value.isEmpty {
                    fields[key] = value
                }
            }
    }

    private func rupiahAmount(from value: String) -> Decimal? {
        let numeric = value
            .uppercased()
            .replacingOccurrences(of: "IDR", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: numeric, locale: Locale(identifier: "en_US_POSIX"))
    }
}
