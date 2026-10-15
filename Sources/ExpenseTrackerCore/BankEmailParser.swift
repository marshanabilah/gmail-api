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
        formatter.isLenient = false
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        let lines = normalizedLines(in: email.body)
        guard lines.contains(where: { $0.caseInsensitiveCompare("Transfer Successful") == .orderedSame }) else {
            return .unsupported
        }
        guard
            let date = field("Date", in: lines),
            let time = field("Time", in: lines),
            let occurredAt = dateFormatter.date(from: "\(date) \(timeWithoutZone(time))"),
            let recipient = recipient(in: lines),
            let amount = rupiahAmount(from: field("Transfer Amount", in: lines) ?? ""),
            amount > 0,
            let referenceNumber = field("Reference No.", in: lines),
            !referenceNumber.isEmpty
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
            confidence: 0.99
        ))
    }

    private func field(_ label: String, in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let cells = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.count == 2,
               cells[0].caseInsensitiveCompare(label) == .orderedSame,
               !cells[1].isEmpty {
                return cells[1]
            }

            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2,
               parts[0].caseInsensitiveCompare(label) == .orderedSame,
               !parts[1].isEmpty {
                return parts[1]
            }

            if line.caseInsensitiveCompare(label) == .orderedSame {
                return lines.dropFirst(index + 1).first { !$0.isEmpty && $0 != ":" }
            }
        }
        return nil
    }

    private func recipient(in lines: [String]) -> String? {
        guard let recipientIndex = lines.firstIndex(where: { $0.caseInsensitiveCompare("Recipient") == .orderedSame }) else {
            return nil
        }
        guard let recipient = lines.dropFirst(recipientIndex + 1).first(where: { !$0.isEmpty && $0 != ":" }) else {
            return nil
        }
        guard !recipient.localizedCaseInsensitiveContains("Bank Mandiri") else { return nil }
        let possibleLabel = recipient.split(maxSplits: 1, whereSeparator: { $0 == "|" || $0 == ":" })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? recipient
        guard !["Date", "Time", "Transfer Amount", "Reference No."].contains(where: {
            possibleLabel.caseInsensitiveCompare($0) == .orderedSame
        }) else { return nil }
        return recipient
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

    private func normalizedLines(in body: String) -> [String] {
        body.components(separatedBy: .newlines).map { line in
            var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") {
                normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized
        }
    }

    private func timeWithoutZone(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+WIB$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

public struct MandiriPaymentEmailParser: BankEmailParsing {
    private let dateFormatter: DateFormatter

    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "d MMM yyyy HH:mm:ss"
        formatter.isLenient = false
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        let lines = normalizedLines(in: email.body)
        guard lines.contains(where: { $0.caseInsensitiveCompare("Payment Successful") == .orderedSame }) else {
            return .unsupported
        }
        guard
            let date = field("Date", in: lines),
            let time = field("Time", in: lines),
            let occurredAt = dateFormatter.date(from: "\(date) \(timeWithoutZone(time))"),
            let recipient = recipient(in: lines),
            let amount = rupiahAmount(from: field("Transaction Amount", in: lines) ?? ""),
            amount > 0,
            let referenceNumber = field("Transaction Ref. No.", in: lines),
            !referenceNumber.isEmpty
        else {
            return .unsupported
        }

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "mandiri",
            occurredAt: occurredAt,
            merchant: recipient,
            amount: amount,
            kind: .qrisPayment,
            confidence: 0.99
        ))
    }

    private func field(_ label: String, in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let cells = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.count == 2,
               cells[0].caseInsensitiveCompare(label) == .orderedSame,
               !cells[1].isEmpty {
                return cells[1]
            }

            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2,
               parts[0].caseInsensitiveCompare(label) == .orderedSame,
               !parts[1].isEmpty {
                return parts[1]
            }

            if line.caseInsensitiveCompare(label) == .orderedSame {
                return lines.dropFirst(index + 1).first { !$0.isEmpty && $0 != ":" }
            }
        }
        return nil
    }

    private func recipient(in lines: [String]) -> String? {
        guard let recipientIndex = lines.firstIndex(where: { $0.caseInsensitiveCompare("Recipient") == .orderedSame }) else {
            return nil
        }
        guard let recipient = lines.dropFirst(recipientIndex + 1).first(where: { !$0.isEmpty && $0 != ":" }) else {
            return nil
        }
        guard !recipient.localizedCaseInsensitiveContains("Bank Mandiri") else { return nil }
        let possibleLabel = recipient.split(maxSplits: 1, whereSeparator: { $0 == "|" || $0 == ":" })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? recipient
        guard !["Date", "Time", "Transaction Amount", "Transaction Ref. No."].contains(where: {
            possibleLabel.caseInsensitiveCompare($0) == .orderedSame
        }) else { return nil }
        guard !possibleLabel.localizedCaseInsensitiveContains("(ID") else { return nil }
        return recipient
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

    private func normalizedLines(in body: String) -> [String] {
        body.components(separatedBy: .newlines).map { line in
            var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") {
                normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized
        }
    }

    private func timeWithoutZone(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+WIB$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

public struct MandiriEMoneyTopUpEmailParser: BankEmailParsing {
    private let dateFormatter: DateFormatter

    public init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "d MMM yyyy HH:mm:ss"
        formatter.isLenient = false
        dateFormatter = formatter
    }

    public func parse(_ email: BankEmail) -> BankEmailParseResult {
        let lines = normalizedLines(in: email.body)
        guard lines.contains(where: { $0.caseInsensitiveCompare("e-money Top-up Successful") == .orderedSame }) else {
            return .unsupported
        }
        guard
            let provider = field("Service Provider", in: lines),
            provider.caseInsensitiveCompare("e-money") == .orderedSame,
            let date = field("Date", in: lines),
            let time = field("Time", in: lines),
            let occurredAt = dateFormatter.date(from: "\(date) \(timeWithoutZone(time))"),
            let amount = rupiahAmount(from: field("Top-up Amount", in: lines) ?? ""),
            amount > 0,
            let referenceNumber = field("Reference Number", in: lines),
            !referenceNumber.isEmpty
        else {
            return .unsupported
        }

        return .transaction(TransactionDraft(
            sourceMessageID: email.messageID,
            bankID: "mandiri",
            occurredAt: occurredAt,
            merchant: "e-money top-up",
            amount: amount,
            kind: .transferOut,
            confidence: 0.99
        ))
    }

    private func field(_ label: String, in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let cells = line.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cells.count == 2,
               cells[0].caseInsensitiveCompare(label) == .orderedSame,
               !cells[1].isEmpty {
                return cells[1]
            }

            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2,
               parts[0].caseInsensitiveCompare(label) == .orderedSame,
               !parts[1].isEmpty {
                return parts[1]
            }

            if line.caseInsensitiveCompare(label) == .orderedSame {
                return lines.dropFirst(index + 1).first { !$0.isEmpty && $0 != ":" }
            }
        }
        return nil
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

    private func normalizedLines(in body: String) -> [String] {
        body.components(separatedBy: .newlines).map { line in
            var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("|") {
                normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized
        }
    }

    private func timeWithoutZone(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+WIB$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
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
        let lines = body
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: \.isNewline)
            .map { line in
                line
                    .replacingOccurrences(of: "|", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }

        let labels = ["Status", "Transaction Date", "Transaction Type", "Payment to", "Total Payment"]
        var fields = [String: String]()

        for (index, line) in lines.enumerated() {
            let inlineParts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if inlineParts.count == 2 {
                let key = inlineParts[0].trimmingCharacters(in: .whitespaces)
                let value = inlineParts[1].trimmingCharacters(in: .whitespaces)
                if labels.contains(key), !value.isEmpty {
                    fields[key] = value
                }
            }

            guard labels.contains(line) else { continue }
            var valueIndex = index + 1
            while lines.indices.contains(valueIndex), lines[valueIndex].isEmpty || lines[valueIndex] == ":" {
                valueIndex += 1
            }
            guard lines.indices.contains(valueIndex) else { continue }
            let value = lines[valueIndex]
            guard !labels.contains(value), !value.isEmpty else { continue }
            fields[line] = value
        }

        return fields
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
