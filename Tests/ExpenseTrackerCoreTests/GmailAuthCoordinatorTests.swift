import ExpenseTrackerCore
import XCTest

@MainActor
final class GmailAuthCoordinatorTests: XCTestCase {
    func testConnectMovesToConnectedWhenTheReadonlyScopeIsGranted() async {
        let account = GmailAuthorizedAccount(
            identifier: "google-user-1",
            email: "marsha@example.com",
            grantedScopes: [GmailOAuthScope.readonly]
        )
        let service = FakeGmailAuthorizationService(authorizationResult: .success(account))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.connect()

        XCTAssertEqual(coordinator.state, .connected(account))
    }

    func testConnectReturnsToDisconnectedWhenTheUserCancels() async {
        let service = FakeGmailAuthorizationService(authorizationResult: .failure(.cancelled))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.connect()

        XCTAssertEqual(coordinator.state, .disconnected)
    }

    func testConnectReportsARecoverableFailureWhenReadonlyScopeIsMissing() async {
        let account = GmailAuthorizedAccount(
            identifier: "google-user-1",
            email: "marsha@example.com",
            grantedScopes: []
        )
        let service = FakeGmailAuthorizationService(authorizationResult: .success(account))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.connect()

        XCTAssertEqual(coordinator.state, .failed(.requiredScopeNotGranted))
    }

    func testRestoreReturnsToDisconnectedWhenNoSessionExists() async {
        let service = FakeGmailAuthorizationService(restoredResult: .success(nil))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .disconnected)
    }

    func testConnectReportsConfigurationFailure() async {
        let service = FakeGmailAuthorizationService(authorizationResult: .failure(.configurationMissing))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.connect()

        XCTAssertEqual(coordinator.state, .failed(.configurationMissing))
    }

    func testRestoreReportsCallbackMismatch() async {
        let service = FakeGmailAuthorizationService(restoredResult: .failure(.callbackMismatch))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .failed(.callbackMismatch))
    }

    func testRestoreReportsInvalidCredential() async {
        let service = FakeGmailAuthorizationService(restoredResult: .failure(.credentialInvalid))
        let coordinator = GmailAuthCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .failed(.credentialInvalid))
    }

    func testDisconnectClearsTheConnectedState() async {
        let account = GmailAuthorizedAccount(
            identifier: "google-user-1",
            email: "marsha@example.com",
            grantedScopes: [GmailOAuthScope.readonly]
        )
        let service = FakeGmailAuthorizationService(restoredResult: .success(account))
        let coordinator = GmailAuthCoordinator(service: service)
        await coordinator.restore()

        await coordinator.disconnect()

        XCTAssertEqual(coordinator.state, .disconnected)
        XCTAssertEqual(service.disconnectCount, 1)
    }
}

@MainActor
private final class FakeGmailAuthorizationService: GmailAuthorizationService {
    var restoredResult: Result<GmailAuthorizedAccount?, GmailAuthorizationFailure>
    var authorizationResult: Result<GmailAuthorizedAccount, GmailAuthorizationFailure>
    private(set) var disconnectCount = 0

    init(
        restoredResult: Result<GmailAuthorizedAccount?, GmailAuthorizationFailure> = .success(nil),
        authorizationResult: Result<GmailAuthorizedAccount, GmailAuthorizationFailure> = .failure(.configurationMissing)
    ) {
        self.restoredResult = restoredResult
        self.authorizationResult = authorizationResult
    }

    func restore() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount? {
        try restoredResult.get()
    }

    func authorize() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount {
        try authorizationResult.get()
    }

    func disconnect() async {
        disconnectCount += 1
    }
}
