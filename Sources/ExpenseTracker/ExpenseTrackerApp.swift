import SwiftData
import SwiftUI

@main
struct ExpenseTrackerApp: App {
    @UIApplicationDelegateAdaptor(LocalNotificationAppDelegate.self) private var notificationDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: TransactionRecord.self,
                MerchantRuleRecord.self,
                TrustedImportRuleRecord.self,
                CategoryRecord.self,
                DiscardedImportRecord.self
            )
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
