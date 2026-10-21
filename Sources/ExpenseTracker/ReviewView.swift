import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TransactionRecord> { $0.status == "needsReview" }, sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @Query private var merchantRules: [MerchantRuleRecord]
    @Query private var trustedImportRules: [TrustedImportRuleRecord]
    @State private var transactionBeingEdited: TransactionRecord?
    @State private var transactionAwaitingDiscard: TransactionRecord?
    @State private var categoryUpdateSummary: String?
    let month: Date?
    let selectMonth: (Date?) -> Void

    private var displayedTransactions: [TransactionRecord] {
        transactions.filter { PendingReviewFilter.matches($0.occurredAt, month: month) }
    }

    private var availableMonths: [Date] {
        Array(Set(transactions.map { SpendingAnalytics.monthStart(for: $0.occurredAt) })).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: Binding(get: { month }, set: selectMonth)) {
                        Text("All pending review").tag(Date?.none)
                        ForEach(availableMonths, id: \.self) { option in
                            Text(option.formatted(.dateTime.year().month(.wide))).tag(Date?.some(option))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if displayedTransactions.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("Imports with uncertain details or no merchant rule will appear here."))
                } else {
                    ForEach(displayedTransactions) { transaction in
                        Section {
                            Button {
                                transactionBeingEdited = transaction
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                            .buttonStyle(.plain)
                            if transaction.category != nil {
                                Button {
                                    accept(transaction)
                                } label: {
                                    Label("Accept", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
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
        .sheet(item: $transactionBeingEdited) { transaction in
            TransactionCategoryEditor(transaction: transaction, acceptsReviewOnSave: true)
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

    private func discard(_ transaction: TransactionRecord) {
        modelContext.insert(DiscardedImportRecord(sourceMessageID: transaction.sourceMessageID))
        modelContext.delete(transaction)
        if (try? modelContext.save()) != nil {
            Task {
                await LocalNotificationScheduler().reconcileReviewReminder(in: modelContext)
            }
        }
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
        createOrUpdateTrustedRule(for: transaction, category: category)
        if (try? modelContext.save()) != nil {
            Task {
                await LocalNotificationScheduler().reconcileReviewReminder(in: modelContext)
            }
        }
    }

    private func createOrUpdateTrustedRule(for transaction: TransactionRecord, category: String) {
        guard let kind = TransactionKind(rawValue: transaction.kind),
              TrustedImportPolicy.isEligibleForAutoImport(merchant: transaction.merchant, kind: kind) else {
            return
        }

        let key = "\(transaction.bankID)|\(TrustedImportPolicy.normalizedMerchantKey(for: transaction.merchant))"
        if let existingRule = trustedImportRules.first(where: { $0.key == key }) {
            existingRule.merchant = transaction.merchant
            existingRule.category = category
        } else {
            modelContext.insert(TrustedImportRuleRecord(
                bankID: transaction.bankID,
                merchant: transaction.merchant,
                category: category
            ))
        }
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

