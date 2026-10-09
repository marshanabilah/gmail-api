import SwiftUI

struct GmailConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Gmail setup") {
                    Text("Create an iOS OAuth client in Google Cloud, then add its client ID and iOS URL scheme to the GmailClientID and GmailRedirectScheme build settings.")
                    Text("The app requests Gmail read-only access. It does not modify or delete mail.")
                }
                Section("First import") {
                    Text("After sign-in is configured, the first mailbox feature will read the Ledger/BCA label for the last 90 days. This screen does not start that import yet.")
                }
            }
            .navigationTitle("Connect Gmail")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
