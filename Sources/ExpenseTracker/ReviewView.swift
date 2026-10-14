import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TransactionRecord> { $0.status == "needsReview" }, sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query(sort: \CategoryRecord.name) private var savedCategories: [CategoryRecord]
    @Query private var merchantRules: [MerchantRuleRecord]
    @State private var transactionAwaitingCategory: TransactionRecord?
    @State private var categoryUpdateSummary: String?

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply saved categories", systemImage: "wand.and.stars") {
                        applySavedCategories()
                    }
                    .disabled(merchantRules.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let categoryUpdateSummary {
                    Text(categoryUpdateSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
            }
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
        let rule: MerchantRuleRecord
        if let existingRule = merchantRules.first(where: {
            $0.merchantContains.caseInsensitiveCompare(transaction.merchant) == .orderedSame
        }) {
            existingRule.category = category
            rule = existingRule
        } else {
            let newRule = MerchantRuleRecord(merchantContains: transaction.merchant, category: category)
            modelContext.insert(newRule)
            rule = newRule
        }

        let categorizer = MerchantCategorizer()
        let merchantRule = MerchantRule(merchantContains: rule.merchantContains, category: rule.category)
        for pendingTransaction in transactions where pendingTransaction.id != transaction.id {
            if categorizer.category(for: pendingTransaction.merchant, rules: [merchantRule]) != nil {
                pendingTransaction.category = rule.category
            }
        }
        try? modelContext.save()
    }

    private func applySavedCategories() {
        let rules = merchantRules.map {
            MerchantRule(merchantContains: $0.merchantContains, category: $0.category)
        }
        let categorizer = MerchantCategorizer()
        var updatedCount = 0

        for transaction in transactions {
            guard let category = categorizer.category(for: transaction.merchant, rules: rules),
                  transaction.category != category else {
                continue
            }
            transaction.category = category
            updatedCount += 1
        }

        if updatedCount > 0 {
            try? modelContext.save()
        }
        categoryUpdateSummary = updatedCount == 1
            ? "Added a saved category to 1 item. It still needs your review."
            : "Added saved categories to \(updatedCount) items. They still need your review."
    }
}
