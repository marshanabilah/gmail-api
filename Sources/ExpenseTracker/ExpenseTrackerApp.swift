import SwiftData
import SwiftUI

@main
struct ExpenseTrackerApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: TransactionRecord.self, MerchantRuleRecord.self, CategoryRecord.self)
        } catch {
            fatalError("Could not create the local transaction store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { GoogleGmailAuthorizationService.handleRedirect($0) }
        }
        .modelContainer(container)
    }
}
