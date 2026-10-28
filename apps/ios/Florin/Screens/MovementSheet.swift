import SwiftUI

/*
 * Un mouvement, pas une opération.
 *
 * La liste replie les deux jambes d'un virement en une seule tuile ; toucher
 * cette tuile ouvrait pourtant la feuille d'une opération — celle de la jambe
 * qui sort, montant négatif, catégorie, « Virement interne ». La tuile dit
 * « CCP → LIVRET A, 240 € » et la feuille répondait « −240 € sur CCP », ce qui
 * n'est pas faux mais n'est pas ce qu'on avait touché.
 *
 * Celle-ci montre le mouvement tel qu'il est lu : un montant sans signe, une
 * date, un départ, une arrivée. Les deux opérations restent accessibles —
 * c'est là que vivent la catégorie, le libellé de banque et la correction.
 */
struct MovementSheet: View {
    /// La jambe qui sort, celle que le pli a gardée : elle porte le compte de
    /// départ, le nom de l'autre et son identifiant.
    let tx: Transaction
    let locale: String
    let currency: String
    let t: Strings
    /// Ouvre la feuille d'opération de cette jambe, une fois celle-ci fermée.
    let onOpenLeg: () -> Void
    /// Supprime les deux lignes. Une seule laisserait un demi-virement, qui
    /// déséquilibre deux soldes au lieu d'un.
    let onDeleteBoth: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var confirming = false

    /// Le nom que porte la tuile : « Virement », sauf si le mouvement a un nom
    /// à lui — une mensualité de prêt en a un, et il dit pourquoi l'argent part.
    private var title: String {
        tx.isPairedRepayment
            ? PayeeText.title(tx.payee, category: tx.categoryName)
            : t("v2.common.ownTransfer", "Virement")
    }

    private var fullDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f.string(from: tx.day)
    }

    /*
     * La hauteur est calculée, comme pour la feuille d'opération.
     *
     * Même raison : un `GeometryReader` en fond rapportait deux cents points
     * de trop et la feuille se calait sur son plafond avec du vide sous le
     * dernier bouton. Le contenu est connu d'avance — un montant, une date, le
     * trajet, deux actions.
     */
    private var sheetHeight: CGFloat {
        var height: CGFloat = 8 + 48 + 12 + 18 + 24   // marge, montant, date
        height += 84 + 24                             // le trajet
        if tx.isPairedRepayment { height += 30 + 12 }  // la pastille du prêt
        if tx.repaymentInterest != nil { height += 18 + 12 }  // intérêts / capital
        height += 2 * 50 + 10                         // les actions
        height += 20 + 16                             // marge basse et poignée
        return height
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    summary
                    route
                    actions
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Florin.bg)
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            t("v2.movement.deleteTitle", "Supprimer ce mouvement ?"),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                working = true
                Task {
                    await onDeleteBoth()
                    dismiss()
                }
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(t("v2.movement.deleteNote",
                   "Les deux lignes du virement seront supprimées, sur les deux comptes."))
        }
    }

    /// Le montant sans signe : un déplacement n'est ni une rentrée ni une
    /// dépense, et le vert comme le rouge lui donneraient un sens qu'il n'a pas.
    private var summary: some View {
        VStack(spacing: 12) {
            AmountText(
                value: abs(tx.amount), locale: locale, currency: currency,
                tone: .neutral, size: 40, weight: .light
            )

            Text(fullDate)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            if tx.isPairedRepayment {
                Pill(text: t("v2.movement.repayment", "Remboursement de prêt"))
            }

            /*
             * Rembourser n'appauvrit pas de ce qu'on rembourse.
             *
             * Seuls les intérêts s'en vont ; le capital passe du compte à la
             * dette, qui baisse d'autant. La liste n'en montre que la part
             * perdue, faute de place ; ici les deux moitiés tiennent, et leur
             * somme est le montant écrit au-dessus.
             */
            if let share = tx.repaymentInterest {
                Text(
                    t(
                        "v2.movement.split",
                        "{interest} d'intérêts · {principal} de capital",
                        [
                            "interest": Money.string(
                                share, locale: locale, currency: currency
                            ),
                            "principal": Money.string(
                                abs(tx.amount) - share, locale: locale, currency: currency
                            ),
                        ]
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
            }
        }
    }

    /*
     * D'où, vers où — et la flèche entre les deux.
     *
     * Deux cartes plutôt qu'une ligne « CCP → LIVRET A » : la tuile de la liste
     * dit déjà le trajet en une ligne, et répéter cette ligne en plus gros
     * n'ajoute rien. Deux blocs étiquetés « Depuis » et « Vers » disent lequel
     * est lequel sans qu'il faille connaître la convention de la flèche.
     */
    private var route: some View {
        HStack(spacing: 10) {
            leg(label: t("v2.movement.from", "Depuis"), account: tx.accountName)

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Florin.text3)

            leg(
                label: t("v2.movement.to", "Vers"),
                account: tx.transferCounterAccount ?? t("v2.common.unknown", "Inconnu")
            )
        }
        .padding(.horizontal, Florin.gutter)
    }

    private func leg(label: String, account: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Florin.text3)
                .textCase(.uppercase)
            Text(account)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Florin.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Florin.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            // Catégorie, libellé de banque, correction : tout cela appartient à
            // une opération, et c'est sa feuille qui le porte déjà.
            SheetAction(
                label: t("v2.movement.openLeg", "Voir l'opération"),
                symbol: "list.bullet.rectangle"
            ) {
                // Demandée d'abord, ouverte ensuite : deux feuilles ne peuvent
                // pas se croiser dans la même image, et réclamer la seconde
                // pendant que la première se referme la perd sans rien dire.
                onOpenLeg()
                dismiss()
            }
            SheetAction(
                label: t("v2.movement.delete", "Supprimer le mouvement"),
                symbol: "trash",
                destructive: true
            ) {
                confirming = true
            }
        }
        .padding(.horizontal, Florin.gutter)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }
}
