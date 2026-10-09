import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TransactionRecord> { $0.status == "needsReview" }, sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    private let categories = ["Food & drink", "Transport", "Shopping", "Bills", "Health", "Other"]

    var body: some View {
        NavigationStack {
            List {
                if transactions.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("Imports with uncertain details or no merchant rule will appear here."))
                } else {
                    ForEach(transactions) { transaction in
                        Section {
                            TransactionRow(transaction: transaction)
                            Menu("Choose category") {
                                ForEach(categories, id: \.self) { category in
                                    Button(category) { approve(transaction, as: category) }
                                }
                            }
                        } header: {
                            Text("Import confidence \(Int(transaction.confidence * 100))%")
                        }
                    }
                }
            }
            .navigationTitle("Review")
        }
    }

    private func approve(_ transaction: TransactionRecord, as category: String) {
        transaction.category = category
        transaction.status = "ready"
        modelContext.insert(MerchantRuleRecord(merchantContains: transaction.merchant, category: category))
        try? modelContext.save()
    }
}
