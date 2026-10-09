import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    let sync: SyncModel

    private var monthTransactions: [TransactionRecord] {
        transactions.filter { Calendar.current.isDate($0.occurredAt, equalTo: .now, toGranularity: .month) }
    }

    private var spending: Decimal {
        monthTransactions
            .filter { ["cardPurchase", "qrisPayment", "fee"].contains($0.kind) }
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
                        Button("Connect Gmail") { sync.start() }
                            .buttonStyle(.borderedProminent)
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
                ToolbarItem(placement: .primaryAction) {
                    Button("Sync Gmail", systemImage: "arrow.triangle.2.circlepath") { sync.start() }
                }
            }
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
