import SwiftUI

struct RootView: View {
    @State private var sync = SyncModel()
    @AppStorage("appearancePreference") private var appearancePreference = AppearancePreference.system.rawValue
    @State private var showsAppearanceSettings = false

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearancePreference)?.colorScheme
    }

    var body: some View {
        TabView {
            DashboardView(sync: sync) { showsAppearanceSettings = true }
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            ReviewView()
                .tabItem { Label("Review", systemImage: "checklist") }
        }
        .tint(.teal)
        .preferredColorScheme(preferredColorScheme)
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
            Button("OK", role: .cancel) { sync.dismissFailure() }
        } message: {
            if case .failed(let message) = sync.state {
                Text(message)
            }
        }
    }
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
