import SwiftUI

struct RootView: View {
    @State private var sync = SyncModel()

    var body: some View {
        TabView {
            DashboardView(sync: sync)
                .tabItem { Label("Dashboard", systemImage: "chart.bar") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            ReviewView()
                .tabItem { Label("Review", systemImage: "checklist") }
        }
        .tint(.teal)
        .sheet(isPresented: $sync.showsConnectionSheet) {
            GmailConnectionView()
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
