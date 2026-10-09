import ExpenseTrackerCore
import Foundation

let recognizedDraft = TransactionDraft(
    sourceMessageID: "message-1",
    bankID: "bca",
    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
    merchant: "Sample Coffee Shop",
    amount: 35_000,
    kind: .qrisPayment,
    confidence: 0.98
)

let recognizedImport = ImportEngine().importDrafts(
    [recognizedDraft],
    existingMessageIDs: [],
    existingFingerprints: [],
    rules: [MerchantRule(merchantContains: "coffee", category: "Food & drink")]
)

precondition(recognizedImport.count == 1)
precondition(recognizedImport[0].category == "Food & drink")
precondition(recognizedImport[0].status == .ready)

let duplicateImport = ImportEngine().importDrafts(
    [recognizedDraft],
    existingMessageIDs: [recognizedDraft.sourceMessageID],
    existingFingerprints: [],
    rules: []
)

precondition(duplicateImport.isEmpty)

let unresolvedDraft = TransactionDraft(
    sourceMessageID: "message-2",
    bankID: "jago",
    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
    merchant: "Sample Merchant",
    amount: 20_000,
    kind: .cardPurchase,
    confidence: 0.98
)

let unresolvedImport = ImportEngine().importDrafts(
    [unresolvedDraft],
    existingMessageIDs: [],
    existingFingerprints: [],
    rules: []
)

precondition(unresolvedImport.first?.status == .needsReview)

let bcaEmail = BankEmail(
    messageID: "bca-message-1",
    sender: "alerts@example.test",
    subject: "Transaction confirmation",
    body: """
    Status : Successful
    Transaction Date : 08 Oct 2026 17:54:32
    Transaction Type : QRIS Payment
    Payment to : Example Store
    Merchant Location : Jakarta, ID
    Total Payment : IDR 3,800.00
    """,
    receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
)

guard case .transaction(let bcaTransaction) = BCAEmailParser().parse(bcaEmail) else {
    preconditionFailure("Expected the BCA sample to parse")
}
precondition(bcaTransaction.bankID == "bca")
precondition(bcaTransaction.kind == .qrisPayment)
precondition(bcaTransaction.merchant == "Example Store")
precondition(bcaTransaction.amount == 3_800)

let jagoEmail = BankEmail(
    messageID: "jago-message-1",
    sender: "alerts@example.test",
    subject: "Debit card transaction",
    body: "You have recently made a transaction of Rp52.200 using your Jago debit card.",
    receivedAt: Date(timeIntervalSince1970: 1_700_000_100)
)

guard case .transaction(let jagoTransaction) = JagoDebitCardEmailParser().parse(jagoEmail) else {
    preconditionFailure("Expected the Jago sample to parse")
}
precondition(jagoTransaction.amount == 52_200)
precondition(jagoTransaction.confidence < 0.9)

let cimbEmail = BankEmail(
    messageID: "cimb-message-1",
    sender: "alerts@example.test",
    subject: "Transaction summary",
    body: """
    Below is the summary of OCTO App transaction that you have performed:
    Date/Time:
    04 October 2026 06:25:00
    Transaction Type:
    Transfer to Own CIMB Niaga Account
    Transfer Amount:
    IDR 100,000.00
    Status:
    SUCCESS
    """,
    receivedAt: Date(timeIntervalSince1970: 1_700_000_200)
)

guard case .transaction(let cimbTransaction) = OCTOCIMBEmailParser().parse(cimbEmail) else {
    preconditionFailure("Expected the OCTO CIMB sample to parse")
}
precondition(cimbTransaction.kind == .transferOut)
precondition(cimbTransaction.amount == 100_000)

let transferImport = ImportEngine().importDrafts(
    [cimbTransaction],
    existingMessageIDs: [],
    existingFingerprints: [],
    rules: []
)
precondition(transferImport.first?.status == .ready)

let mandiriEmail = BankEmail(
    messageID: "mandiri-message-1",
    sender: "alerts@example.test",
    subject: "Transfer Successful",
    body: """
    Transfer Successful
    Recipient
    Example Recipient
    Bank Mandiri - 1234
    Date | 2 Oct 2026
    Time | 14:00:45 WIB
    Transfer Amount | Rp 700.338,00
    """,
    receivedAt: Date(timeIntervalSince1970: 1_700_000_300)
)

guard case .transaction(let mandiriTransaction) = MandiriTransferEmailParser().parse(mandiriEmail) else {
    preconditionFailure("Expected the Mandiri sample to parse")
}
precondition(mandiriTransaction.kind == .transferOut)
precondition(mandiriTransaction.merchant == "Example Recipient")
precondition(mandiriTransaction.amount == Decimal(string: "700338.00"))

let mandiriImport = ImportEngine().importDrafts(
    [mandiriTransaction],
    existingMessageIDs: [],
    existingFingerprints: [],
    rules: []
)
precondition(mandiriImport.first?.status == .needsReview)
print("Core verification passed")
