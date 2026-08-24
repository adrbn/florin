import SwiftUI

/// Where the user points the app at their own Florin.
struct SetupView: View {
    @EnvironmentObject private var server: ServerStore
    @Environment(\.dismiss) private var dismiss

    let isFirstRun: Bool
    @State private var draft = ""
    @State private var token = ""
    @State private var status: ServerStatus = .unknown

    private var preview: URL? { ServerStore.normalise(draft) }

    var body: some View {
        NavigationStack {
            Form {
                ServerFields(host: $draft, token: $token, status: $status)

                Section {
                    Button(isFirstRun ? "Ouvrir Florin" : "Enregistrer", action: save)
                        .disabled(preview == nil)
                } footer: {
                    Text(
                        "Rien ne quitte ton réseau : l'app affiche simplement ton propre serveur Florin."
                    )
                }
            }
            .navigationTitle(isFirstRun ? "Bienvenue" : "Serveur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstRun {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            draft = server.rawURL.isEmpty ? ServerStore.suggestedHost : server.rawURL
            token = server.apiToken
        }
    }

    private func save() {
        guard preview != nil else { return }
        server.apiToken = token
        server.apply(draft)
        if !isFirstRun { dismiss() }
    }
}
