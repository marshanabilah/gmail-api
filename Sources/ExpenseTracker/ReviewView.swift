import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TransactionRecord> { $0.status == "needsReview" }, sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query(sort: \CategoryRecord.name) private var savedCategories: [CategoryRecord]
    @State private var transactionAwaitingCategory: TransactionRecord?

    private var categories: [String] {
        ExpenseCategory.availableNames(savedNames: savedCategories.map(\.name))
    }

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
                                Divider()
                                Button("Add category", systemImage: "plus") {
                                    transactionAwaitingCategory = transaction
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
        .sheet(item: $transactionAwaitingCategory) { transaction in
            NewCategoryView(existingNames: categories) { newCategory in
                approve(transaction, as: newCategory)
            }
        }
    }

    private func approve(_ transaction: TransactionRecord, as category: String) {
        transaction.category = category
        transaction.status = "ready"
        modelContext.insert(MerchantRuleRecord(merchantContains: transaction.merchant, category: category))
        try? modelContext.save()
    }
}
