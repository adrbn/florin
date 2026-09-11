import SwiftUI

/// Les marchands renommés, pour les retrouver.
///
/// On renomme depuis une opération, là où l'on voit le nom qui ne dit rien.
/// Cette liste sert à l'inverse : revoir ce qu'on a nommé, corriger une faute
/// de frappe, ou rendre à un marchand le nom de sa banque.
struct MerchantsScreen: View {
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var names = MerchantNames.shared
    @ObservedObject private var logos = MerchantLogos.shared
    @State private var editing: Editing?
    @State private var failure: String?

    struct Editing: Identifiable {
        let key: String
        var id: String { key }
    }

    var body: some View {
        let merchants = names.all()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if merchants.isEmpty {
                        Text(t(
                            "v2.merchants.empty",
                            "Aucun marchand renommé. Touchez le nom d'une opération pour lui donner le vôtre."
                        ))
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Florin.gutter)
                        .padding(.top, 40)
                    } else {
                        RowGroup {
                            ForEach(Array(merchants.enumerated()), id: \.element.key) { index, merchant in
                                if index > 0 { Hairline() }
                                row(key: merchant.key, name: merchant.name)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                    }
                }
                .padding(.vertical, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(t("v2.merchants.title", "Marchands renommés"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.settings.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $editing) { pending in
            MerchantNameSheet(key: pending.key, bankLabel: pending.key.uppercased(), t: t)
        }
        .alert(
            t("v2.merchants.title", "Marchands renommés"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func row(key: String, name: String) -> some View {
        HStack(spacing: 12) {
            let face = logos.face(forKey: key)
            Bubble(label: key, emoji: face?.emoji, size: 34, logo: face?.logo)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(key.uppercased())
                    .font(.system(size: 11.5))
                    .foregroundStyle(Florin.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                editing = Editing(key: key)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.text2)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("v2.merchant.title", "Renommer le marchand"))
            Button {
                do {
                    try MerchantNames.shared.rename(key: key, to: "")
                } catch {
                    failure = error.localizedDescription
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Florin.negative)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("v2.merchant.reset", "Revenir au nom de la banque"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }
}
