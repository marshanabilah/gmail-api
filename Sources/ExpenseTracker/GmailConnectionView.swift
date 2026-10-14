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
                    Text("After sign-in is configured, sync reads the Transaction label for the last 90 days. It does not change or delete your email.")
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
