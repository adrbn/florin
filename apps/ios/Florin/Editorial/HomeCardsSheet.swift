import SwiftUI

/*
 * Quelles cartes, dans quel ordre, de quelle couleur.
 *
 * Les trois réponses étaient éparpillées : masquer une carte se faisait compte
 * par compte, en ouvrant chacun depuis l'écran Comptes ; l'ordre se changeait
 * dans la liste de cet écran, deux onglets plus loin ; la couleur n'était le
 * choix de personne — un hachage de l'identifiant, donc une teinte tirée au
 * sort et stable, ce qui n'est pas la même chose que choisie.
 *
 * Elles tiennent en une page parce que c'est une seule question posée trois
 * fois : à quoi ressemble ma pile. La place est celle que le bouton
 * « Ajouter » occupait à tort — on ouvre un compte une fois par an, on range
 * sa pile le jour où elle grandit.
 *
 * Tout s'écrit au doigt, rien ne se valide : `display_order` et
 * `display_color` sont des colonnes de la base, la liste des cartes écartées
 * une clé de réglages. Il n'y a donc pas d'état à perdre, et rien à reposer au
 * lancement suivant.
 */
struct HomeCardsSheet: View {
    let accounts: [Account]
    var t: Strings = .device
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeCards.key) private var hiddenCards = ""

    /// L'ordre affiché, qui devient l'ordre écrit. Tenu en état plutôt que
    /// relu : une liste qui se réordonne sous le doigt doit bouger pendant le
    /// geste, pas après l'aller-retour en base.
    @State private var order: [Account]
    /// Le rang de teinte choisi, par compte. L'`Account` en main garde celui
    /// qu'il avait au chargement de la feuille ; c'est ici qu'on sait ce qui
    /// vient d'être tapé.
    @State private var slots: [String: Int]
    /// La ligne dont le nuancier est ouvert. Une seule à la fois.
    @State private var picking: String?

    init(accounts: [Account], t: Strings = .device, onChange: @escaping () -> Void) {
        self.accounts = accounts
        self.t = t
        self.onChange = onChange
        _order = State(initialValue: accounts)
        _slots = State(initialValue: accounts.reduce(into: [:]) { out, account in
            if let slot = HomeCards.colorSlot(account.displayColor) { out[account.id] = slot }
        })
    }

    private var hidden: Set<String> { HomeCards.hidden(hiddenCards) }

    /// Les teintes telles que la pile les dessine, et non une approximation :
    /// même fonction, mêmes collisions écartées de la même façon.
    private var tints: [String: Color] {
        HomeCards.palette(order.map { account in
            var copy = account
            copy.displayColor = slots[account.id].map(HomeCards.slotName)
            return copy
        })
    }

    var body: some View {
        List {
            ForEach(order) { account in
                row(account)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Florin.text.opacity(0.08))
                    .listRowInsets(EdgeInsets(
                        top: 0, leading: Ed.gutter, bottom: 0, trailing: Ed.gutter
                    ))
            }
            /*
             * Le glisser-déposer sans mode édition.
             *
             * `onMove` suffit : une liste qui le porte se réordonne à l'appui
             * long, et c'est le geste de Wallet. Passer la liste en
             * `editMode: .active` donnerait la poignée tout de suite — et
             * assommerait les boutons de chaque ligne, qui sont les deux
             * autres réponses de cette page. La poignée visible coûtait l'œil
             * et la couleur.
             */
            .onMove { from, to in
                order.move(fromOffsets: from, toOffset: to)
                AccountsLogic.reorder(order)
                onChange()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header.background(Florin.bg) }
        .background(Florin.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EdPill(text: t("v2.ed.cards.title", "Cartes"))
                Spacer(minLength: 8)
                EdIconButton(symbol: "xmark", label: t("v2.common.close", "Fermer")) { dismiss() }
                    .padding(.trailing, -10)
            }
            // Un geste invisible a besoin d'un mot : rien sur une ligne ne dit
            // qu'elle se déplace.
            Text(t(
                "v2.ed.cards.hint",
                "Celles qui sont allumées s'empilent sur l'accueil. Appui long sur une ligne pour changer l'ordre."
            ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func row(_ account: Account) -> some View {
        let shown = !hidden.contains(account.id)
        let tint = tints[account.id] ?? Florin.text
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    picking = picking == account.id ? nil : account.id
                } label: {
                    Circle()
                        .fill(tint)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Florin.text.opacity(0.18), lineWidth: 1))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t("v2.ed.cards.color", "Couleur")))

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    hiddenCards = HomeCards.write(account.id, shown: !shown, in: hiddenCards)
                } label: {
                    HStack(spacing: 10) {
                        Text(account.name)
                            .font(.system(size: 17, weight: .medium))
                            // Un compte écarté reste lisible : c'est une
                            // ligne qu'on va rallumer, pas une ligne morte.
                            .foregroundStyle(shown ? Florin.text : Florin.text3)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(shown ? Florin.text : Florin.text3)
                    }
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if picking == account.id { swatches(account) }
        }
    }

    /// Les huit teintes de la série, plus le retour à l'automatique.
    private func swatches(_ account: Account) -> some View {
        HStack(spacing: 10) {
            ForEach(0 ..< Florin.series.count, id: \.self) { slot in
                swatch(fill: Florin.series[slot], picked: slots[account.id] == slot) {
                    slots[account.id] = slot
                    AccountsLogic.setColor(account.id, slot: slot)
                }
            }
            // L'automatique n'est pas une couleur : il n'en montre donc aucune.
            swatch(
                fill: Florin.text.opacity(0.10), picked: slots[account.id] == nil,
                label: t("v2.ed.cards.auto", "Automatique")
            ) {
                slots[account.id] = nil
                AccountsLogic.setColor(account.id, slot: nil)
            }
        }
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    private func swatch(
        fill: Color, picked: Bool, label: String? = nil, tap: @escaping () -> Void
    ) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            tap()
            onChange()
        } label: {
            Circle()
                .fill(fill)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(
                        picked ? Florin.text : Florin.text.opacity(0.18),
                        lineWidth: picked ? 2 : 1
                    )
                )
                .overlay {
                    if label != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Florin.text2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label ?? ""))
    }
}
