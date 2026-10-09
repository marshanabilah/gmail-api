import SwiftUI

struct GmailConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Before you connect") {
                    Text("Create an iOS OAuth client in your Google Cloud project and add its client ID and redirect scheme to the app configuration.")
                    Text("The app will request Gmail read-only access and use transaction emails only. It should not request permission to modify or delete mail.")
                }
                Section("What we still need") {
                    Text("Redacted transaction-email samples from Mandiri, BCA, Jago, and OCTO CIMB. Each bank parser needs real message formats before it can import safely.")
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
