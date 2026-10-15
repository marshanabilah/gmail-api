import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Query(sort: \TransactionRecord.occurredAt, order: .reverse) private var transactions: [TransactionRecord]
    @State private var showsManualEntry = false
    @State private var transactionBeingEdited: TransactionRecord?
    @State private var displayMode: TransactionsDisplayMode = .transactions
    @State private var selectedMonth = SpendingAnalytics.monthStart(for: .now)
    @State private var analyticsDetail: TransactionAnalyticsDetail?
    let openReview: (Date) -> Void

    private var analyticsInputs: [SpendingAnalyticsInput] {
        transactions.map {
            SpendingAnalyticsInput(
                occurredAt: $0.occurredAt,
                amount: $0.amount,
                kind: TransactionKind(rawValue: $0.kind) ?? .unknown,
                category: $0.category,
                status: ImportStatus(rawValue: $0.status) ?? .needsReview,
                source: $0.bankID
            )
        }
    }

    private var availableMonths: [Date] {
        SpendingAnalytics.availableMonths(transactions: analyticsInputs)
    }

    private var monthlySummary: MonthlySpendingSummary {
        SpendingAnalytics.summary(for: selectedMonth, transactions: analyticsInputs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $displayMode) {
                        ForEach(TransactionsDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if displayMode == .transactions {
                    transactionList
                } else {
                    analyticsList
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
        .sheet(item: $transactionBeingEdited) { transaction in
            TransactionCategoryEditor(transaction: transaction)
        }
        .sheet(item: $analyticsDetail) { detail in
            NavigationStack {
                MonthlyTransactionDetailView(detail: detail, transactions: transactions)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { analyticsDetail = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var transactionList: some View {
        if transactions.isEmpty {
            ContentUnavailableView(
                "No transactions",
                systemImage: "list.bullet.rectangle",
                description: Text("Run a Gmail sync or add a transaction to see it here.")
            )
        } else {
            ForEach(transactions) { transaction in
                Button {
                    transactionBeingEdited = transaction
                } label: {
                    TransactionRow(transaction: transaction)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit category for \(transaction.merchant)")
            }
        }
    }

    @ViewBuilder
    private var analyticsList: some View {
        Section("Spending") {
            Picker("Month", selection: $selectedMonth) {
                ForEach(availableMonths, id: \.self) { month in
                    Text(month.formatted(.dateTime.year().month(.wide))).tag(month)
                }
            }
            LabeledContent("Confirmed spending", value: monthlySummary.confirmedSpending, format: .currency(code: "IDR"))
            if monthlySummary.pendingReviewCount > 0 {
                Button {
                    openReview(selectedMonth)
                } label: {
                    LabeledContent("Pending review", value: monthlySummary.pendingReviewAmount, format: .currency(code: "IDR"))
                }
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
                        AnalyticsTotalRow(title: category.category, amount: category.amount)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(category.category) transactions")
                }
            }
        }

        Section("By source") {
            if monthlySummary.sources.isEmpty {
                Text("No confirmed spending for this month.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(monthlySummary.sources, id: \.source) { source in
                    Button {
                        analyticsDetail = .source(month: selectedMonth, source: source.source)
                    } label: {
                        AnalyticsTotalRow(title: source.source, amount: source.amount)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(source.source) transactions")
                }
            }
        }

        Section("Activity") {
            Button("View activity for \(selectedMonth.formatted(.dateTime.year().month(.wide)))") {
                analyticsDetail = .month(selectedMonth)
            }
        }
    }
}

private enum TransactionsDisplayMode: CaseIterable, Identifiable {
    case transactions
    case analytics

    var id: Self { self }

    var title: String {
        switch self {
        case .transactions: "Transactions"
        case .analytics: "Analytics"
        }
    }
}

private struct AnalyticsTotalRow: View {
    let title: String
    let amount: Decimal

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount, format: .currency(code: "IDR"))
                .foregroundStyle(.secondary)
        }
    }
}

private enum TransactionAnalyticsDetail: Identifiable {
    case month(Date)
    case category(month: Date, category: String)
    case source(month: Date, source: String)

    var id: String {
        switch self {
        case .month(let month):
            "month-\(month.timeIntervalSinceReferenceDate)"
        case .category(let month, let category):
            "category-\(month.timeIntervalSinceReferenceDate)-\(category)"
        case .source(let month, let source):
            "source-\(month.timeIntervalSinceReferenceDate)-\(source)"
        }
    }

    var month: Date {
        switch self {
        case .month(let month), .category(let month, _), .source(let month, _):
            month
        }
    }

    var title: String {
        switch self {
        case .month(let month):
            month.formatted(.dateTime.year().month(.wide))
        case .category(_, let category):
            category
        case .source(_, let source):
            source
        }
    }
}

private struct MonthlyTransactionDetailView: View {
    let detail: TransactionAnalyticsDetail
    let transactions: [TransactionRecord]
    @State private var transactionBeingEdited: TransactionRecord?

    private var filteredTransactions: [TransactionRecord] {
        transactions.filter { transaction in
            guard Calendar.current.isDate(transaction.occurredAt, equalTo: detail.month, toGranularity: .month) else {
                return false
            }
            switch detail {
            case .month:
                return true
            case .category(_, let category):
                return isConfirmedExpense(transaction)
                    && SpendingAnalytics.categoryName(for: transaction.category) == category
            case .source(_, let source):
                return isConfirmedExpense(transaction)
                    && SpendingAnalytics.sourceName(for: transaction.bankID) == source
            }
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
                    Button {
                        transactionBeingEdited = transaction
                    } label: {
                        TransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit category for \(transaction.merchant)")
                }
            }
        }
        .navigationTitle(detail.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $transactionBeingEdited) { transaction in
            TransactionCategoryEditor(transaction: transaction)
        }
    }

    private func isConfirmedExpense(_ transaction: TransactionRecord) -> Bool {
        SpendingAnalytics.isConfirmedExpense(
            kind: TransactionKind(rawValue: transaction.kind) ?? .unknown,
            status: ImportStatus(rawValue: transaction.status) ?? .needsReview
        )
    }

    private var emptyStateDescription: String {
        switch detail {
        case .month:
            "No transactions were recorded in the selected month."
        case .category:
            "No confirmed spending matches this category in the selected month."
        case .source:
            "No confirmed spending matches this source in the selected month."
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

struct TransactionCategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryRecord.name) private var savedCategories: [CategoryRecord]
    @Query private var merchantRules: [MerchantRuleRecord]
    let transaction: TransactionRecord
    let preservesReviewStatus: Bool

    @State private var description: String
    @State private var category: String
    @State private var remembersMerchant = false
    @State private var showsNewCategory = false
    @State private var showsDeleteConfirmation = false
    @State private var validationMessage: String?

    init(transaction: TransactionRecord, preservesReviewStatus: Bool = false) {
        self.transaction = transaction
        self.preservesReviewStatus = preservesReviewStatus
        _description = State(initialValue: transaction.merchant)
        _category = State(initialValue: transaction.category ?? "Food & drink")
    }

    private var categories: [String] {
        ExpenseCategory.availableNames(
            savedNames: savedCategories.map(\.name) + [transaction.category].compactMap { $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Description", text: $description)
                        .textContentType(.none)
                    LabeledContent("Amount", value: transaction.amount, format: .currency(code: "IDR"))
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    Button("Add category", systemImage: "plus") {
                        showsNewCategory = true
                    }
                }

                Section {
                    Toggle("Use for future transactions from this merchant", isOn: $remembersMerchant)
                } footer: {
                    Text("This does not recategorize transactions you already saved.")
                }

                Section {
                    Button("Delete transaction", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit transaction")
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
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from this iPhone. If it came from Gmail, it will not return after a later sync. Gmail is unchanged.")
        }
    }

    private func save() {
        guard let normalizedDescription = TransactionDescription.normalized(description) else {
            validationMessage = "Add a description so you can recognize this transaction later."
            return
        }
        transaction.merchant = normalizedDescription
        transaction.category = category
        if transaction.status == ImportStatus.needsReview.rawValue, !preservesReviewStatus {
            transaction.status = ImportStatus.ready.rawValue
        }
        if remembersMerchant {
            if let existingRule = merchantRules.first(where: {
                $0.merchantContains.caseInsensitiveCompare(transaction.merchant) == .orderedSame
            }) {
                existingRule.category = category
            } else {
                modelContext.insert(MerchantRuleRecord(merchantContains: transaction.merchant, category: category))
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = "Could not save the category. Try again."
        }
    }

    private func deleteTransaction() {
        if TransactionDeletion.shouldSuppressFutureImport(bankID: transaction.bankID) {
            modelContext.insert(DiscardedImportRecord(sourceMessageID: transaction.sourceMessageID))
        }
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = "Could not delete this transaction. Try again."
        }
    }
}
