import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TransactionRecord> { $0.status == "needsReview" }, sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query(sort: \CategoryRecord.name) private var savedCategories: [CategoryRecord]
    @Query private var merchantRules: [MerchantRuleRecord]
    @State private var transactionAwaitingCategory: TransactionRecord?
    @State private var transactionAwaitingDiscard: TransactionRecord?
    @State private var categoryUpdateSummary: String?
    let month: Date?
    let showAll: () -> Void

    private var displayedTransactions: [TransactionRecord] {
        transactions.filter { PendingReviewFilter.matches($0.occurredAt, month: month) }
    }

    private var categories: [String] {
        ExpenseCategory.availableNames(savedNames: savedCategories.map(\.name))
    }

    var body: some View {
        NavigationStack {
            List {
                if displayedTransactions.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("Imports with uncertain details or no merchant rule will appear here."))
                } else {
                    ForEach(displayedTransactions) { transaction in
                        Section {
                            TransactionRow(transaction: transaction)
                            if transaction.category != nil {
                                Button {
                                    accept(transaction)
                                } label: {
                                    Label("Accept", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                            Menu {
                                ForEach(categories, id: \.self) { category in
                                    Button {
                                        chooseCategory(transaction, as: category)
                                    } label: {
                                        Label(
                                            category,
                                            systemImage: transaction.category == category ? "checkmark" : "circle"
                                        )
                                    }
                                }
                                Divider()
                                Button("Add category", systemImage: "plus") {
                                    transactionAwaitingCategory = transaction
                                }
                            } label: {
                                Label(transaction.category ?? "Choose category", systemImage: "tag")
                            }
                            Button(role: .destructive) {
                                transactionAwaitingDiscard = transaction
                            } label: {
                                Label("Discard", systemImage: "trash")
                            }
                        } header: {
                            Text("Import confidence \(Int(transaction.confidence * 100))%")
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                if let month {
                    ToolbarItem(placement: .principal) {
                        Text("Showing: \(month.formatted(.dateTime.year().month(.wide)))")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Show all") { showAll() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Match saved categories", systemImage: "arrow.triangle.branch") {
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
                chooseCategory(transaction, as: newCategory)
            }
        }
        .confirmationDialog(
            "Discard this transaction?",
            isPresented: Binding(
                get: { transactionAwaitingDiscard != nil },
                set: { if !$0 { transactionAwaitingDiscard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                if let transactionAwaitingDiscard {
                    discard(transactionAwaitingDiscard)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the transaction from this iPhone and keeps the same Gmail email from returning after a later sync.")
        }
    }

    private func chooseCategory(_ transaction: TransactionRecord, as category: String) {
        transaction.category = category
        categoryUpdateSummary = nil
        accept(transaction)
    }

    private func discard(_ transaction: TransactionRecord) {
        modelContext.insert(DiscardedImportRecord(sourceMessageID: transaction.sourceMessageID))
        modelContext.delete(transaction)
        try? modelContext.save()
        transactionAwaitingDiscard = nil
    }

    private func accept(_ transaction: TransactionRecord) {
        guard let category = transaction.category else { return }
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
            ? "Matched 1 item. Tap Accept when it looks right."
            : "Matched \(updatedCount) items. Tap Accept when they look right."
    }
}
