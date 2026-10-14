import SwiftData
import SwiftUI
import GoogleSignInSwift

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var merchantRuleRecords: [MerchantRuleRecord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsDisconnectConfirmation = false
    @State private var bcaImportPreview: BCAReviewImportResult?
    @State private var bcaImportSummary: String?
    @State private var selectedMonth = SpendingAnalytics.monthStart(for: .now)
    @State private var analyticsDetail: AnalyticsDetail?
    let sync: SyncModel
    let openSettings: () -> Void

    private var analyticsInputs: [SpendingAnalyticsInput] {
        transactions.map {
            SpendingAnalyticsInput(
                occurredAt: $0.occurredAt,
                amount: $0.amount,
                kind: TransactionKind(rawValue: $0.kind) ?? .unknown,
                category: $0.category,
                status: ImportStatus(rawValue: $0.status) ?? .needsReview
            )
        }
    }

    private var availableMonths: [Date] {
        SpendingAnalytics.availableMonths(transactions: analyticsInputs)
    }

    private var monthlySummary: MonthlySpendingSummary {
        SpendingAnalytics.summary(for: selectedMonth, transactions: analyticsInputs)
    }

    private var monthTransactions: [TransactionRecord] {
        transactions.filter { Calendar.current.isDate($0.occurredAt, equalTo: selectedMonth, toGranularity: .month) }
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
                            Picker("Month", selection: $selectedMonth) {
                                ForEach(availableMonths, id: \.self) { month in
                                    Text(month.formatted(.dateTime.year().month(.wide))).tag(month)
                                }
                            }
                            LabeledContent("Confirmed spending", value: monthlySummary.confirmedSpending, format: .currency(code: "IDR"))
                            if monthlySummary.pendingReviewCount > 0 {
                                LabeledContent("Pending review", value: monthlySummary.pendingReviewAmount, format: .currency(code: "IDR"))
                                    .foregroundStyle(.orange)
                                Text("\(monthlySummary.pendingReviewCount) \(monthlySummary.pendingReviewCount == 1 ? "transaction still needs" : "transactions still need") your confirmation.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("By category") {
                            if monthlySummary.categories.isEmpty {
                                Text("No confirmed spending for this month.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(monthlySummary.categories, id: \.category) { category in
                                    Button {
                                        analyticsDetail = .category(month: selectedMonth, category: category.category)
                                    } label: {
                                        HStack {
                                            Text(category.category)
                                            Spacer()
                                            Text(category.amount, format: .currency(code: "IDR"))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("View \(category.category) transactions")
                                }
                            }
                        }

                        Section("Activity") {
                            ForEach(monthTransactions.prefix(5)) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                            Button("View all activity") {
                                analyticsDetail = .month(selectedMonth)
                            }
                        }

                        if let candidateCount = sync.lastSyncCandidateCount {
                            Section("Gmail") {
                                Text(candidateCountDescription(candidateCount))
                                    .foregroundStyle(.secondary)
                                Button("Import BCA payments", systemImage: "tray.and.arrow.down") {
                                    prepareBCAImport()
                                }
                                if let bcaImportSummary {
                                    Text(bcaImportSummary)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
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
        .sheet(item: $analyticsDetail) { detail in
            NavigationStack {
                MonthlyTransactionDetailView(
                    month: detail.month,
                    category: detail.category,
                    transactions: transactions
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { analyticsDetail = nil }
                    }
                }
            }
        }
        .confirmationDialog(
            "Import BCA payments?",
            isPresented: Binding(
                get: { bcaImportPreview != nil },
                set: { if !$0 { bcaImportPreview = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let bcaImportPreview {
                Button("Import \(bcaImportPreview.imports.count) payments") {
                    saveBCAImport(bcaImportPreview)
                }
            }
            Button("Cancel", role: .cancel) { bcaImportPreview = nil }
        } message: {
            if let bcaImportPreview {
                Text(bcaImportConfirmationMessage(bcaImportPreview))
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
            syncButton
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

    private func candidateCountDescription(_ count: Int) -> String {
        "\(count) eligible \(count == 1 ? "email was" : "emails were") found. They have not been added to the ledger yet."
    }

    private func prepareBCAImport() {
        let preview = sync.bcaReviewPreview(
            existingMessageIDs: Set(transactions.map(\.sourceMessageID)),
            existingFingerprints: Set(transactions.map(\.fingerprint)),
            rules: merchantRules
        )
        guard let preview else {
            bcaImportSummary = "Sync Gmail again before preparing transactions for Review."
            return
        }
        guard !preview.imports.isEmpty else {
            bcaImportSummary = "No new successful BCA QRIS payments were ready to import. Other emails were left untouched."
            return
        }
        bcaImportPreview = preview
    }

    private var merchantRules: [MerchantRule] {
        merchantRuleRecords.map {
            MerchantRule(merchantContains: $0.merchantContains, category: $0.category)
        }
    }

    private func saveBCAImport(_ preview: BCAReviewImportResult) {
        if sync.saveBCAReviewImports(preview, in: modelContext) {
            bcaImportSummary = "Added \(preview.imports.count) BCA \(preview.imports.count == 1 ? "payment" : "payments") to Review."
        } else {
            bcaImportSummary = "The BCA payments were not saved. Your existing ledger was left unchanged."
        }
        bcaImportPreview = nil
    }

    private func bcaImportConfirmationMessage(_ preview: BCAReviewImportResult) -> String {
        var details = ["Every payment will start in Review. Saved category rules can suggest a category, but you decide when to accept it."]
        if preview.duplicateCount > 0 {
            details.append("\(preview.duplicateCount) duplicate \(preview.duplicateCount == 1 ? "email was" : "emails were") skipped.")
        }
        let leftUntouched = preview.ignoredCount + preview.unsupportedCount
        if leftUntouched > 0 {
            details.append("\(leftUntouched) other \(leftUntouched == 1 ? "email was" : "emails were") left untouched.")
        }
        return details.joined(separator: " ")
    }
}

private enum AnalyticsDetail: Identifiable {
    case month(Date)
    case category(month: Date, category: String)

    var id: String {
        switch self {
        case .month(let month):
            "month-\(month.timeIntervalSinceReferenceDate)"
        case .category(let month, let category):
            "category-\(month.timeIntervalSinceReferenceDate)-\(category)"
        }
    }

    var month: Date {
        switch self {
        case .month(let month), .category(let month, _):
            month
        }
    }

    var category: String? {
        switch self {
        case .month:
            nil
        case .category(_, let category):
            category
        }
    }
}

struct TransactionRow: View {
    let transaction: TransactionRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(transaction.bankID.uppercased()) · \(transaction.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transaction.merchant)
                    .font(.body.weight(.medium))
                Text(transaction.category ?? "Needs category")
                    .font(.caption)
                    .foregroundStyle(transaction.status == "needsReview" ? .orange : .secondary)
            }
            Spacer(minLength: 8)
            Text(transaction.amount, format: .currency(code: "IDR"))
                .font(.body.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MonthlyTransactionDetailView: View {
    let month: Date
    let category: String?
    let transactions: [TransactionRecord]

    private var filteredTransactions: [TransactionRecord] {
        transactions.filter { transaction in
            guard Calendar.current.isDate(transaction.occurredAt, equalTo: month, toGranularity: .month) else {
                return false
            }
            guard let category else { return true }
            let kind = TransactionKind(rawValue: transaction.kind) ?? .unknown
            let status = ImportStatus(rawValue: transaction.status) ?? .needsReview
            return SpendingAnalytics.isConfirmedExpense(kind: kind, status: status)
                && SpendingAnalytics.categoryName(for: transaction.category) == category
        }
    }

    var body: some View {
        List {
            if filteredTransactions.isEmpty {
                ContentUnavailableView(
                    "No transactions",
                    systemImage: "list.bullet",
                    description: Text(emptyStateDescription)
                )
            } else {
                ForEach(filteredTransactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        category ?? month.formatted(.dateTime.year().month(.wide))
    }

    private var emptyStateDescription: String {
        if category != nil {
            return "No confirmed spending matches this category in the selected month."
        }
        return "No transactions were recorded in the selected month."
    }
}
