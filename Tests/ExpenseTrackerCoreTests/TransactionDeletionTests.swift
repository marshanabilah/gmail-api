import XCTest
@testable import ExpenseTrackerCore

final class TransactionDeletionTests: XCTestCase {
    func testManualTransactionDoesNotNeedAnImportSuppressionMarker() {
        XCTAssertFalse(TransactionDeletion.shouldSuppressFutureImport(bankID: ManualTransactionSource.eWallet.rawValue))
    }

    func testImportedBankTransactionNeedsAnImportSuppressionMarker() {
        XCTAssertTrue(TransactionDeletion.shouldSuppressFutureImport(bankID: "bca"))
    }
}
