import Foundation
import GoogleSignIn

final class GoogleGmailMailboxClient: GmailMailboxClient, @unchecked Sendable {
    private let decoder: GmailMessageBodyDecoder

    init(decoder: GmailMessageBodyDecoder = GmailMessageBodyDecoder()) {
        self.decoder = decoder
    }

    func listLabels() async throws(GmailMailboxFailure) -> [GmailLabel] {
        let response: LabelsResponse = try await request(path: "/gmail/v1/users/me/labels", queryItems: [])
        return response.labels.map { GmailLabel(id: $0.id, name: $0.name) }
    }

    func messagePage(
        in labelID: String,
        after startDate: Date,
        pageToken: String?
    ) async throws(GmailMailboxFailure) -> GmailMessagePage {
        var queryItems = [
            URLQueryItem(name: "labelIds", value: labelID),
            URLQueryItem(name: "q", value: "after:\(Int(startDate.timeIntervalSince1970))"),
            URLQueryItem(name: "maxResults", value: "500")
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        let response: MessageListResponse = try await request(
            path: "/gmail/v1/users/me/messages",
            queryItems: queryItems
        )
        return GmailMessagePage(
            messageIDs: response.messages?.map(\.id) ?? [],
            nextPageToken: response.nextPageToken
        )
    }

    func message(id: String) async throws(GmailMailboxFailure) -> BankEmail {
        let response: MessageResponse = try await request(
            path: "/gmail/v1/users/me/messages/\(id)",
            queryItems: [],
            forbiddenFailure: .messageUnavailable
        )
        guard
            let timestampMilliseconds = Double(response.internalDate),
            let payload = response.payload
        else {
            throw .malformedResponse
        }

        let receivedAt = Date(timeIntervalSince1970: timestampMilliseconds / 1_000)
        let body = try decoder.decode(payload.domainPart)
        return BankEmail(
            messageID: response.id,
            sender: response.payload?.header(named: "From") ?? "",
            subject: response.payload?.header(named: "Subject") ?? "",
            body: body,
            receivedAt: receivedAt
        )
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        forbiddenFailure: GmailMailboxFailure = .authorizationExpired
    ) async throws(GmailMailboxFailure) -> Response {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw .authorizationExpired
        }

        let accessToken: String
        do {
            accessToken = try await user.refreshTokensIfNeeded().accessToken.tokenString
        } catch {
            let nsError = error as NSError
            throw GmailTokenRefreshFailureClassifier.mailboxFailure(
                errorDomain: nsError.domain,
                errorCode: nsError.code
            )
        }

        guard var components = URLComponents(string: "https://gmail.googleapis.com\(path)") else {
            throw .malformedResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw .malformedResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailMailboxFailure.unavailable
            }
            switch httpResponse.statusCode {
            case 200 ... 299:
                break
            case 401:
                throw GmailMailboxFailure.authorizationExpired
            case 403:
                throw forbiddenFailure
            case 429, 500 ... 599:
                throw GmailMailboxFailure.unavailable
            default:
                throw GmailMailboxFailure.malformedResponse
            }

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw GmailMailboxFailure.malformedResponse
            }
        } catch let failure as GmailMailboxFailure {
            throw failure
        } catch {
            throw .unavailable
        }
    }
}

private struct LabelsResponse: Decodable {
    let labels: [LabelResponse]
}

private struct LabelResponse: Decodable {
    let id: String
    let name: String
}

private struct MessageListResponse: Decodable {
    let messages: [MessageReference]?
    let nextPageToken: String?
}

private struct MessageReference: Decodable {
    let id: String
}

private struct MessageResponse: Decodable {
    let id: String
    let internalDate: String
    let payload: MessagePartResponse?
}

private struct MessagePartResponse: Decodable {
    let mimeType: String
    let headers: [MessageHeader]?
    let body: MessagePartBody?
    let parts: [MessagePartResponse]?

    var domainPart: GmailMessagePart {
        GmailMessagePart(
            mimeType: mimeType,
            bodyData: body?.data,
            parts: parts?.map(\.domainPart) ?? []
        )
    }

    func header(named name: String) -> String? {
        headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct MessageHeader: Decodable {
    let name: String
    let value: String
}

private struct MessagePartBody: Decodable {
    let data: String?
}
