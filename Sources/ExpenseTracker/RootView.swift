import SwiftUI

struct RootView: View {
    @State private var sync = SyncModel()
    @AppStorage("appearancePreference") private var appearancePreference = AppearancePreference.system.rawValue
    @State private var showsAppearanceSettings = false
    @State private var selectedTab = AppTab.dashboard
    @State private var reviewMonth: Date?

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearancePreference)?.colorScheme
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(sync: sync, openReview: {
                reviewMonth = SpendingAnalytics.monthStart(for: .now)
                selectedTab = .review
            }) { showsAppearanceSettings = true }
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }
                .tag(AppTab.dashboard)

            TransactionsView { month in
                reviewMonth = month
                selectedTab = .review
            }
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(AppTab.transactions)

            ReviewView(month: reviewMonth, selectMonth: { reviewMonth = $0 })
                .tabItem { Label("Review", systemImage: "checklist") }
                .tag(AppTab.review)
        }
        .tint(.teal)
        .preferredColorScheme(preferredColorScheme)
        .task { sync.restoreConnection() }
        .sheet(isPresented: $sync.showsConnectionSheet) {
            GmailConnectionView()
        }
        .sheet(isPresented: $showsAppearanceSettings) {
            AppearanceSettingsView(selection: $appearancePreference)
        }
        .alert("Gmail sync needs setup", isPresented: Binding(
            get: { if case .failed = sync.state { return true }; return false },
            set: { if !$0 { sync.dismissFailure() } }
        )) {
            if sync.canRetryMailboxSync {
                Button("Retry sync") { sync.retryMailboxSync() }
            }
            Button("OK", role: .cancel) { sync.dismissFailure() }
        } message: {
            if case .failed(let message) = sync.state {
                Text(message)
            }
        }
    }
}

private enum AppTab: Hashable {
    case dashboard
    case transactions
    case review
}

private enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    var body: some View {
        NavigationStack {
            Form {
                Picker("Appearance", selection: $selection) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                Text("System follows your iPhone setting. Light and Dark keep the ledger in that appearance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Appearance")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
