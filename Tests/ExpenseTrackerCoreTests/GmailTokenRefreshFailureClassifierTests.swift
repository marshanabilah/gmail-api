import XCTest
@testable import ExpenseTrackerCore

final class GmailTokenRefreshFailureClassifierTests: XCTestCase {
    func testExpiredGoogleRefreshTokenRequiresReconnection() {
        XCTAssertEqual(
            GmailTokenRefreshFailureClassifier.mailboxFailure(
                errorDomain: "com.google.GIDSignIn",
                errorCode: -11
            ),
            .authorizationExpired
        )
    }

    func testOtherRefreshFailureCanBeRetriedWithoutReconnection() {
        XCTAssertEqual(
            GmailTokenRefreshFailureClassifier.mailboxFailure(
                errorDomain: "NSURLErrorDomain",
                errorCode: -1009
            ),
            .unavailable
        )
    }
}
