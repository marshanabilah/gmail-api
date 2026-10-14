import SwiftData
import SwiftUI
import GoogleSignInSwift

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsDisconnectConfirmation = false
    let sync: SyncModel
    let openSettings: () -> Void

    private var monthTransactions: [TransactionRecord] {
        transactions.filter { Calendar.current.isDate($0.occurredAt, equalTo: .now, toGranularity: .month) }
    }

    private var spending: Decimal {
        monthTransactions
            .filter { ["cardPurchase", "qrisPayment", "fee", "manualExpense"].contains($0.kind) }
            .reduce(0) { $0 + $1.amount }
    }

    private var reviewCount: Int {
        transactions.filter { $0.status == "needsReview" }.count
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
                        Section("This month") {
                            LabeledContent("Spending", value: spending, format: .currency(code: "IDR"))
                            if reviewCount > 0 {
                                LabeledContent("Needs review", value: "\(reviewCount)")
                                    .foregroundStyle(.orange)
                            }
                        }

                        Section("Recent imports") {
                            ForEach(monthTransactions.prefix(5)) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                        }

                        if let candidateCount = sync.lastSyncCandidateCount {
                            Section("Gmail") {
                                Text(candidateCountDescription(candidateCount))
                                    .foregroundStyle(.secondary)
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
