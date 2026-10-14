import Foundation

public struct GmailMessagePart: Sendable {
    public let mimeType: String
    public let bodyData: String?
    public let parts: [GmailMessagePart]

    public init(mimeType: String, bodyData: String?, parts: [GmailMessagePart] = []) {
        self.mimeType = mimeType
        self.bodyData = bodyData
        self.parts = parts
    }
}

public struct GmailMessageBodyDecoder: Sendable {
    public init() {}

    public func decode(_ payload: GmailMessagePart) throws(GmailMailboxFailure) -> String {
        let parts = flattenedParts(in: payload)
        if let plainText = try decodedText(in: parts, matching: "text/plain") {
            return plainText
        }
        if let html = try decodedText(in: parts, matching: "text/html") {
            return plainText(fromHTML: html)
        }
        throw .malformedResponse
    }

    private func flattenedParts(in part: GmailMessagePart) -> [GmailMessagePart] {
        [part] + part.parts.flatMap(flattenedParts)
    }

    private func decodedText(
        in parts: [GmailMessagePart],
        matching mimeType: String
    ) throws(GmailMailboxFailure) -> String? {
        for part in parts where part.mimeType.caseInsensitiveCompare(mimeType) == .orderedSame {
            guard let bodyData = part.bodyData, !bodyData.isEmpty else { continue }
            return try decodeBase64URL(bodyData)
        }
        return nil
    }

    private func decodeBase64URL(_ value: String) throws(GmailMailboxFailure) -> String {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch normalized.count % 4 {
        case 0: break
        case 2: normalized += "=="
        case 3: normalized += "="
        default: throw .malformedResponse
        }

        guard let data = Data(base64Encoded: normalized), let text = String(data: data, encoding: .utf8) else {
            throw .malformedResponse
        }
        return text
    }

    private func plainText(fromHTML html: String) -> String {
        let withLineBreaks = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"</(?:p|div|li|tr|h[1-6])\s*>"#, with: "\n", options: .regularExpression)
        let withoutTags = withLineBreaks.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let decodedEntities = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        return decodedEntities
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
