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
                        Label("No imports yet", systemImage: "tray")
                    } description: {
                        Text("Connect Gmail, then sync bank transaction emails to start your ledger.")
                    } actions: {
                        GoogleSignInButton(
                            scheme: colorScheme == .dark ? .dark : .light,
                            action: sync.start
                        )
                        .accessibilityLabel("Connect Gmail with Google")
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
                        Button("Disconnect Gmail", systemImage: "person.crop.circle.badge.xmark") { showsDisconnectConfirmation = true }
                    case .connecting:
                        ProgressView()
                    case .idle, .syncing, .failed:
                        Button("Connect Gmail", systemImage: "envelope.badge") { sync.start() }
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
