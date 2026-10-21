import SwiftData
import SwiftUI
import GoogleSignInSwift

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var merchantRuleRecords: [MerchantRuleRecord]
    @Query private var trustedImportRuleRecords: [TrustedImportRuleRecord]
    @Query private var discardedImportRecords: [DiscardedImportRecord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsDisconnectConfirmation = false
    @State private var bankImportPreview: BankReviewImportResult?
    @State private var bankImportSummary: String?
    let sync: SyncModel
    let openReview: () -> Void
    let openSettings: () -> Void

    private var analyticsInputs: [SpendingAnalyticsInput] {
        transactions.map {
            SpendingAnalyticsInput(
                occurredAt: $0.occurredAt,
                amount: $0.amount,
                kind: TransactionKind(rawValue: $0.kind) ?? .unknown,
                category: $0.category,
                status: ImportStatus(rawValue: $0.status) ?? .needsReview,
                source: $0.bankID
            )
        }
    }

    private var currentMonthSummary: MonthlySpendingSummary {
        SpendingAnalytics.summary(for: .now, transactions: analyticsInputs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: emptyStateSymbol)
                    } description: {
                        Text(emptyStateDescription)
                    } actions: {
                        emptyStateAction
                    }
                } else {
                    List {
                        Section("Spending") {
                            LabeledContent("This month", value: currentMonthSummary.confirmedSpending, format: .currency(code: "IDR"))
                            if currentMonthSummary.pendingReviewCount > 0 {
                                Button(action: openReview) {
                                    LabeledContent("Pending review", value: currentMonthSummary.pendingReviewAmount, format: .currency(code: "IDR"))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.orange)
                                Text("\(currentMonthSummary.pendingReviewCount) \(currentMonthSummary.pendingReviewCount == 1 ? "transaction still needs" : "transactions still need") your confirmation.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        gmailSection

                        Section("Activity") {
                            ForEach(transactions.prefix(5)) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ledger")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: openSettings) {
                        Label("Appearance", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    switch sync.state {
                    case .connected:
                        syncButton
                    case .connecting:
                        ProgressView()
                    case .syncing:
                        ProgressView()
                            .accessibilityLabel("Syncing Gmail")
                    case .failed where sync.canRetryMailboxSync:
                        Button("Retry Gmail sync", systemImage: "arrow.clockwise") { sync.retryMailboxSync() }
                    case .idle, .failed:
                        Button("Connect Gmail", systemImage: "envelope.badge") { sync.start() }
                    }
                }
                if case .connected = sync.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Disconnect Gmail", systemImage: "person.crop.circle.badge.xmark") { showsDisconnectConfirmation = true }
                    }
                }
            }
        }
        .confirmationDialog("Disconnect Gmail?", isPresented: $showsDisconnectConfirmation, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { sync.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Gmail access from this iPhone. Your transactions and categories stay on the device.")
        }
        .confirmationDialog(
            "Import bank transactions?",
            isPresented: Binding(
                get: { bankImportPreview != nil },
                set: { if !$0 { bankImportPreview = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let bankImportPreview {
                Button("Import \(bankImportPreview.imports.count) \(bankImportPreview.imports.count == 1 ? "transaction" : "transactions")") {
                    saveBankImport(bankImportPreview)
                }
            }
            Button("Cancel", role: .cancel) { bankImportPreview = nil }
        } message: {
            if let bankImportPreview {
                Text(bankImportConfirmationMessage(bankImportPreview))
            }
        }
    }

    private var emptyStateTitle: String {
        switch sync.state {
        case .connected:
            "No imported transactions"
        case .syncing:
            "Checking Transaction"
        case .failed:
            "Gmail needs attention"
        case .idle, .connecting:
            "No imports yet"
        }
    }

    private func skippedMessageDescription(_ count: Int) -> String {
        if count == 1 {
            return "Gmail did not return 1 labeled message, so the app skipped it."
        }
        return "Gmail did not return \(count) labeled messages, so the app skipped them."
    }

    private var emptyStateSymbol: String {
        switch sync.state {
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .idle, .connecting, .connected:
            "tray"
        }
    }

    private var emptyStateDescription: String {
        switch sync.state {
        case .connected:
            if let candidateCount = sync.lastSyncCandidateCount {
                return candidateCountDescription(candidateCount)
            }
            return "Sync your Transaction label to check bank transaction emails from the last 90 days."
        case .syncing:
            return "Reading the Transaction label. No transactions are added to the ledger yet."
        case .failed:
            return "Try syncing again, or connect Gmail again if access has expired."
        case .idle, .connecting:
            return "Connect Gmail, then sync bank transaction emails to start your ledger."
        }
    }

    @ViewBuilder
    private var emptyStateAction: some View {
        switch sync.state {
        case .connected:
            if sync.lastSyncCandidateCount != nil {
                importButton
            } else {
                syncButton
            }
        case .syncing:
            ProgressView("Syncing Gmail")
        case .failed where sync.canRetryMailboxSync:
            Button("Retry Gmail sync", systemImage: "arrow.clockwise") { sync.retryMailboxSync() }
        case .idle, .connecting, .failed:
            GoogleSignInButton(
                scheme: colorScheme == .dark ? .dark : .light,
                action: sync.start
            )
            .accessibilityLabel("Connect Gmail with Google")
        }
    }

    private var syncButton: some View {
        Button("Sync Gmail", systemImage: "arrow.triangle.2.circlepath") { sync.syncMailbox() }
            .accessibilityHint("Reads the Transaction label for the last 90 days")
    }

    private var importButton: some View {
        Button("Import transactions", systemImage: "tray.and.arrow.down") {
            prepareBankImport()
        }
    }

    @ViewBuilder
    private var gmailSection: some View {
        if let candidateCount = sync.lastSyncCandidateCount {
            Section("Gmail") {
                Text(candidateCountDescription(candidateCount))
                    .foregroundStyle(.secondary)
                if sync.lastSyncSkippedMessageCount > 0 {
                    Text(skippedMessageDescription(sync.lastSyncSkippedMessageCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                importButton
                if let bankImportSummary {
                    Text(bankImportSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func candidateCountDescription(_ count: Int) -> String {
        "\(count) eligible \(count == 1 ? "email was" : "emails were") found. They have not been added to the ledger yet."
    }

    private func prepareBankImport() {
        let preview = sync.bankReviewPreview(
            existingMessageIDs: Set(transactions.map(\.sourceMessageID)),
            existingFingerprints: Set(transactions.map(\.fingerprint)),
            discardedMessageIDs: Set(discardedImportRecords.map(\.sourceMessageID)),
            rules: merchantRules,
            trustedRules: trustedImportRules
        )
        guard let preview else {
            bankImportSummary = "Sync Gmail again before preparing transactions for Review."
            return
        }
        guard !preview.imports.isEmpty else {
            bankImportSummary = emptyBankImportSummary(preview)
            return
        }
        bankImportPreview = preview
    }

    private var merchantRules: [MerchantRule] {
        merchantRuleRecords.map {
            MerchantRule(merchantContains: $0.merchantContains, category: $0.category)
        }
    }

    private var trustedImportRules: [TrustedImportRule] {
        trustedImportRuleRecords.map {
            TrustedImportRule(bankID: $0.bankID, merchant: $0.merchant, category: $0.category)
        }
    }

    private func saveBankImport(_ preview: BankReviewImportResult) {
        if sync.saveBankReviewImports(preview, in: modelContext) {
            bankImportSummary = importSummary(preview)
            Task {
                await LocalNotificationScheduler().reconcileReviewReminder(in: modelContext)
            }
        } else {
            bankImportSummary = "The transactions were not saved. Your existing ledger was left unchanged."
        }
        bankImportPreview = nil
    }

    private func bankImportConfirmationMessage(_ preview: BankReviewImportResult) -> String {
        var details = ["Trusted exact merchant matches will go directly to Transactions. All other imported transactions will start in Review."]
        if preview.duplicateCount > 0 {
            details.append("\(preview.duplicateCount) duplicate \(preview.duplicateCount == 1 ? "email was" : "emails were") skipped.")
        }
        let leftUntouched = preview.ignoredCount + preview.unsupportedCount
        if leftUntouched > 0 {
            details.append("\(leftUntouched) other \(leftUntouched == 1 ? "email was" : "emails were") left untouched.")
        }
        return details.joined(separator: " ")
    }

    private func importSummary(_ preview: BankReviewImportResult) -> String {
        let readyCount = preview.imports.filter { $0.status == .ready }.count
        let reviewCount = preview.imports.count - readyCount
        var details = [String]()

        if readyCount > 0 {
            details.append("Added \(readyCount) \(readyCount == 1 ? "transaction" : "transactions") directly to Transactions.")
        }
        if reviewCount > 0 {
            details.append("Added \(reviewCount) \(reviewCount == 1 ? "transaction" : "transactions") to Review.")
        }
        return details.joined(separator: " ")
    }

    private func emptyBankImportSummary(_ preview: BankReviewImportResult) -> String {
        var details = ["Import finished. Nothing new was added to Review."]
        if preview.duplicateCount > 0 {
            details.append("\(preview.duplicateCount) \(preview.duplicateCount == 1 ? "matching transaction was" : "matching transactions were") already in your ledger.")
        }
        let unsupported = preview.ignoredCount + preview.unsupportedCount
        if unsupported > 0 {
            details.append("\(unsupported) \(unsupported == 1 ? "email could not" : "emails could not") be added to Review, so the app left \(unsupported == 1 ? "it" : "them") untouched.")
        }
        return details.joined(separator: " ")
    }
}

struct TransactionRow: View {
    let transaction: TransactionRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(SpendingAnalytics.sourceName(for: transaction.bankID)) · \(transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transaction.merchant)
                    .font(.body.weight(.medium))
                Text(reviewCategoryLabel)
                    .font(.caption)
                    .foregroundStyle(transaction.status == "needsReview" ? .orange : .secondary)
            }
            Spacer(minLength: 8)
            Text(transaction.amount, format: .currency(code: "IDR"))
                .font(.body.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var reviewCategoryLabel: String {
        guard transaction.status == "needsReview" else {
            return transaction.category ?? "Uncategorized"
        }
        guard let category = transaction.category else {
            return "Needs category"
        }
        return "Suggested: \(category)"
    }
}
