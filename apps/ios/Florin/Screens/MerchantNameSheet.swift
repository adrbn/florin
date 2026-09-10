import SwiftUI

/// Donner à un marchand le nom sous lequel on le connaît.
///
/// Un seul champ, et deux phrases qui disent ce que le geste fait : ce qu'on
/// renomme, dans les mots de la banque, et combien d'opérations changent de
/// nom — toutes celles de ce marchand, passées et à venir. Sans ce compte, on
/// ne saurait pas si l'on renomme une ligne ou trois ans d'historique.
struct MerchantNameSheet: View {
    let key: String
    /// Le libellé de la banque, nettoyé : ce qu'on renomme, dit en clair.
    let bankLabel: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var count: Int?
    @State private var failure: String?
    @FocusState private var focused: Bool

    private let existing: String?

    init(key: String, bankLabel: String, t: Strings) {
        self.key = key
        self.bankLabel = bankLabel
        self.t = t
        let existing = MerchantNames.shared.name(forKey: key)
        self.existing = existing
        _name = State(initialValue: existing ?? "")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != existing }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: t("v2.merchant.name", "Nom affiché"))
                    TextField(PayeeText.bankName(bankLabel), text: $name)
                        .font(.system(size: 17))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save(trimmed) } }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 16)
                        .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(t(
                        "v2.merchant.bankLabel", "Libellé de la banque : {label}",
                        ["label": bankLabel]
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .lineLimit(2)
                }

                if let count {
                    Text(t(
                        "v2.merchant.reach",
                        "S'applique à ses {count} opérations, et à celles qui arriveront.",
                        ["count": count]
                    ))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Florin.text2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button { save(trimmed) } label: {
                    Text(t("v2.merchant.save", "Renommer"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Florin.accent, in: Capsule())
                        .opacity(canSave ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                if existing != nil {
                    Button { save("") } label: {
                        Text(t("v2.merchant.reset", "Revenir au nom de la banque"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.negative)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.top, 8)
            .navigationTitle(t("v2.merchant.title", "Renommer le marchand"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.activity.tint, floor: true) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            count = MerchantNames.shared.usage(ofKey: key)
            focused = true
        }
        .alert(
            t("v2.merchant.title", "Renommer le marchand"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func save(_ value: String) {
        do {
            try MerchantNames.shared.rename(key: key, to: value)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
