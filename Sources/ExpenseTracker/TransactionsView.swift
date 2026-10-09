import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @State private var showsManualEntry = false

    var body: some View {
        NavigationStack {
            List {
                if transactions.isEmpty {
                    ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle", description: Text("Run a Gmail sync to see imported transaction emails here."))
                } else {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsManualEntry = true } label: {
                        Label("Add transaction", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showsManualEntry) {
            ManualTransactionView()
        }
    }
}

private struct ManualTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryRecord.name) private var savedCategories: [CategoryRecord]
    @State private var merchant = ""
    @State private var amount = ""
    @State private var occurredAt = Date()
    @State private var source: ManualTransactionSource = .cash
    @State private var category = "Food & drink"
    @State private var validationMessage: String?
    @State private var showsNewCategory = false

    private var categories: [String] {
        ExpenseCategory.availableNames(savedNames: savedCategories.map(\.name))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("What was it for?", text: $merchant)
                        .textContentType(.none)
                    TextField("Amount in IDR", text: $amount)
                        .keyboardType(.numberPad)
                    DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Source") {
                    Picker("Paid with", selection: $source) {
                        ForEach(ManualTransactionSource.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    Button("Add category", systemImage: "plus") {
                        showsNewCategory = true
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .sheet(isPresented: $showsNewCategory) {
            NewCategoryView(existingNames: categories) { newCategory in
                category = newCategory
            }
        }
    }

    private func save() {
        let digitsOnly = amount.filter(\.isNumber)
        guard let amountValue = Decimal(string: digitsOnly), amountValue > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }

        let input = ManualTransactionInput(
            merchant: merchant,
            amount: amountValue,
            occurredAt: occurredAt,
            source: source,
            category: category
        )
        guard let draft = input.makeDraft(id: "manual-\(UUID().uuidString)") else {
            validationMessage = "Add a description so you can recognize this transaction later."
            return
        }

        modelContext.insert(TransactionRecord(
            sourceMessageID: draft.sourceMessageID,
            fingerprint: draft.fingerprint,
            bankID: draft.bankID,
            occurredAt: draft.occurredAt,
            merchant: draft.merchant,
            amount: draft.amount,
            kind: draft.kind.rawValue,
            confidence: draft.confidence,
            category: category,
            status: "ready"
        ))
        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = "Could not save this transaction. Try again."
        }
    }
}

struct NewCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let existingNames: [String]
    let didSave: (String) -> Void

    @State private var name = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Category name", text: $name)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        guard let normalizedName = ExpenseCategory.customName(from: name, existingNames: existingNames) else {
            validationMessage = "Choose a name that is not already in your categories."
            return
        }

        modelContext.insert(CategoryRecord(name: normalizedName))
        do {
            try modelContext.save()
            didSave(normalizedName)
            dismiss()
        } catch {
            validationMessage = "Could not save this category. Try again."
        }
    }
}
