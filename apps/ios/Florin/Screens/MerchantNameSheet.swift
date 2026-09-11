import SwiftUI

/// Donner à un marchand le nom sous lequel on le connaît, et sa tête.
///
/// Le nom, puis ce que montre sa bulle : le logo pris sur son site, ou un
/// emoji. En haut, la bulle telle qu'elle apparaîtra, qui change pendant qu'on
/// tape. En bas, combien d'opérations sont concernées — toutes celles de ce
/// marchand, passées et à venir. Sans ce compte, on ne saurait pas si l'on
/// modifie une ligne ou trois ans d'historique.
struct MerchantNameSheet: View {
    let key: String
    /// Le libellé de la banque, nettoyé : ce qu'on renomme, dit en clair.
    let bankLabel: String
    let t: Strings
    /// What the row shows without a logo, so the preview matches it.
    var categoryEmoji: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logos = MerchantLogos.shared
    @State private var name: String
    @State private var site: String
    @State private var emoji: String
    /// Le site de l'aperçu, pris une fois la frappe posée : pas une requête
    /// par lettre tapée.
    @State private var previewSite: String?
    @State private var count: Int?
    @State private var failure: String?
    @FocusState private var focused: Bool

    private let existing: String?
    private let existingMark: MerchantLogos.Mark?

    init(key: String, bankLabel: String, t: Strings, categoryEmoji: String? = nil) {
        self.key = key
        self.bankLabel = bankLabel
        self.t = t
        self.categoryEmoji = categoryEmoji
        let existing = MerchantNames.shared.name(forKey: key)
        self.existing = existing
        let mark = MerchantLogos.shared.mark(forKey: key)
        self.existingMark = mark
        _name = State(initialValue: existing ?? "")
        _site = State(initialValue: mark?.domain ?? "")
        _emoji = State(initialValue: mark?.emoji ?? "")
        _previewSite = State(initialValue: mark?.domain)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var typedSite: String { site.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var domain: String? { MerchantLogos.normalizedDomain(typedSite) }
    private var siteIsValid: Bool { typedSite.isEmpty || domain != nil }
    /// The name being typed counts first: renaming a label "Netflix" shows
    /// Netflix's logo before saving.
    private var known: String? {
        KnownMerchants.domain(forKey: key)
            ?? (trimmed.isEmpty ? nil : KnownMerchants.domain(forKey: trimmed))
            ?? logos.knownDomain(forKey: key)
    }

    private var nameChanged: Bool { trimmed != (existing ?? "") }
    private var markChanged: Bool {
        domain != existingMark?.domain || (emoji.isEmpty ? nil : emoji) != existingMark?.emoji
    }
    private var canSave: Bool { siteIsValid && (nameChanged || markChanged) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: t("v2.merchant.name", "Nom affiché"))
                        TextField(PayeeText.bankName(bankLabel), text: $name)
                            .font(.system(size: 17))
                            .focused($focused)
                            .submitLabel(.done)
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                            .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: t("v2.merchant.logo", "Logo"))
                        HStack(spacing: 10) {
                            TextField(
                                known ?? t("v2.merchant.sitePlaceholder", "exemple.fr"),
                                text: $site
                            )
                            .font(.system(size: 17))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                            .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                            // A glyph, not an emoji, when empty: a coloured 🙂 there
                            // read as one already chosen.
                            TextField("", text: $emoji)
                                .font(.system(size: 22))
                                .overlay {
                                    if emoji.isEmpty {
                                        Image(systemName: "face.smiling")
                                            .font(.system(size: 20))
                                            .foregroundStyle(Florin.text3)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .padding(.vertical, 9)
                                .florinGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onChange(of: emoji) { _, new in
                                    let kept = new.last(where: Self.isEmoji).map(String.init) ?? ""
                                    if kept != new { emoji = kept }
                                }
                        }
                        Text(siteIsValid
                            ? t("v2.merchant.logoHint", "Le logo vient de ce site, sauf si vous choisissez un emoji")
                            : t("v2.merchant.badSite", "Ce n'est pas une adresse de site"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(siteIsValid ? Florin.text3 : Florin.negative)
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

                    Button { save() } label: {
                        Text(t("v2.common.save", "Enregistrer"))
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
                        Button { save(name: "") } label: {
                            Text(t("v2.merchant.reset", "Revenir au nom de la banque"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Florin.negative)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(t("v2.merchant.title", "Renommer le marchand"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.cancel", "Annuler")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.activity.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            count = MerchantNames.shared.usage(ofKey: key)
            focused = true
        }
        .task(id: typedSite) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            previewSite = domain
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

    /// La bulle et le nom, comme dans la liste des opérations.
    private var preview: some View {
        let site = typedSite.isEmpty ? known : previewSite
        let logo = emoji.isEmpty && logos.enabled ? site.flatMap(logos.logo(domain:)) : nil
        return HStack(spacing: 14) {
            Bubble(label: bankLabel, emoji: emoji.isEmpty ? categoryEmoji : emoji, size: 52, logo: logo)
            VStack(alignment: .leading, spacing: 3) {
                Text(trimmed.isEmpty ? PayeeText.bankName(bankLabel) : trimmed)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(bankLabel)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .florinSurface()
    }

    private func save(name reset: String? = nil) {
        let newName = reset ?? trimmed
        do {
            if newName != (existing ?? "") { try MerchantNames.shared.rename(key: key, to: newName) }
            if markChanged {
                try logos.setMark(key: key, domain: domain, emoji: emoji.isEmpty ? nil : emoji)
            }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A pictograph, not a digit or a "#" — which Unicode also counts as emoji.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        if scalars.contains(where: \.properties.isEmojiPresentation) { return true }
        return scalars.count > 1 && scalars.first?.properties.isEmoji == true
    }
}
