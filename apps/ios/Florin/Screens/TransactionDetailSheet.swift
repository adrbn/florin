import SwiftUI

/// One transaction, in a real sheet.
///
/// This replaces the web popup that misbehaved inside the native shell: an HTML
/// bottom sheet has to re-implement detents, drag-to-dismiss, scroll locking and
/// keyboard avoidance, and each of those was a separate bug. A `presentationDetents`
/// sheet gets all four from the OS, and the native tab bar no longer has to be
/// told to move out of its way.
struct TransactionDetailSheet: View {
    let tx: Transaction
    let categories: [Category]
    /// Where the money could have gone, for the transfer question below.
    let accounts: [Account]
    let locale: String
    let currency: String
    let t: Strings
    let onPatch: (TxPatch) async -> Void
    let onDelete: () async -> Void
    let onAttachTransfer: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    /// The category chosen in this visit. The row this sheet was handed is a
    /// value from a list that has not refetched, so it still says "sans
    /// catégorie" a moment after one was assigned.
    @State private var filed: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var working = false
    @State private var filing = false
    @State private var markingTransfer = false
    /// Chosen inside the picker, acted on once the picker has closed: two
    /// sheets cannot change places in the same frame, and asking for the
    /// second one while the first is still dismissing silently drops it.
    @State private var wantsTransfer = false
    @State private var naming = false
    /// Observed so the title changes the moment the merchant is renamed.
    @ObservedObject private var names = MerchantNames.shared

    /*
     * La hauteur est calculée, pas mesurée.
     *
     * Un `GeometryReader` en fond du contenu rapportait deux cent cinquante
     * points de trop : la feuille se calait sur son plafond avec autant de
     * vide sous le dernier bouton. Trois tentatives pour arriver à cette
     * conclusion, et une seule expérience l'a tranchée — remplacer la valeur
     * mesurée par une constante a immédiatement donné la bonne feuille, donc
     * le mécanisme n'était pas en cause, seule la mesure l'était.
     *
     * Le contenu de cette feuille est entièrement connu à l'avance : un
     * montant, une date, deux à quatre pastilles, un libellé de banque, et de
     * trois à cinq actions. On l'additionne. C'est approximatif de quelques
     * points et toujours juste à l'œil, là où la mesure était exacte en
     * théorie et fausse en pratique.
     */
    private var sheetHeight: CGFloat {
        var height: CGFloat = 8 + 48 + 12 + 18 + 12   // marge, montant, date
        height += pillRows * 30 + 12
        if let memo = tx.memo, !memo.isEmpty {
            // Le libellé brut d'une banque tient rarement sur une ligne.
            height += CGFloat(min(4, memo.count / 38 + 1)) * 18 + 10
        }
        height += 22                                   // entre le résumé et les actions
        height += CGFloat(actionCount) * 50 + CGFloat(actionCount - 1) * 10
        height += 20 + 16                              // marge basse et poignée
        return min(height, 720)
    }

    /// Compte, catégorie, « à vérifier », « virement » — la rangée passe à deux
    /// lignes dès la troisième.
    private var pillRows: CGFloat {
        let pills = 2 + (tx.needsReview ? 1 : 0) + (tx.isTransfer ? 1 : 0)
        return pills > 2 ? 2 : 1
    }

    private var actionCount: Int {
        var n = 3   // catégoriser, modifier, supprimer
        if tx.needsReview { n += 1 }
        if !tx.isTransfer, tx.amount < 0, accounts.count > 1 { n += 1 }
        return n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    summary
                    actions
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(PayeeText.humanize(tx.payee))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                /*
                 * Le titre est le nom du marchand, et c'est là qu'on le change.
                 *
                 * Un bouton de plus dans la liste d'actions aurait allongé la
                 * feuille pour un geste rare ; « Modifier », lui, touche le
                 * libellé de cette seule opération. Toucher le nom pour le
                 * renommer est l'endroit où on le chercherait, et le crayon
                 * dit qu'on peut.
                 */
                ToolbarItem(placement: .principal) {
                    Button { naming = true } label: {
                        HStack(spacing: 6) {
                            Text(PayeeText.humanize(tx.payee))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Florin.text)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Florin.text3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(t("v2.merchant.title", "Renommer le marchand"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    // A glyph, not the word. "Fermer" in a toolbar draws a
                    // capsule wide enough to read as the sheet's main action,
                    // which is the one thing it is not.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel(t("v2.common.close", "Fermer"))
                }
            }
        }
        /*
         * As tall as it needs to be.
         *
         * A medium detent is half the screen whatever the sheet contains, so a
         * transaction with four actions had its last one — the red delete —
         * cut through the middle, and one with two left a void underneath. The
         * height is the content's, plus the navigation bar and the home
         * indicator; `.large` stays available for a long memo.
         */
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
        /*
         * Le fond passe à la feuille, comme dans les six autres.
         *
         * Il était posé sur le ScrollView — donc sur la vue même dont on
         * mesure le contenu pour dimensionner le volet. La feuille se calait
         * pile sur son plafond de 720 points, signature d'une boucle : la
         * mesure nourrit la hauteur, la hauteur renourrit la mesure, et
         * l'ensemble se stabilise au maximum autorisé avec trois cents points
         * de vide sous le dernier bouton.
         *
         * `presentationBackground` peint la surface présentée sans participer
         * à la mise en page du contenu, ce qui sort la mesure de la boucle.
         */
        .presentationBackground { Backdrop(tint: TabRoute.activity.tint, floor: true) }
        .sheet(isPresented: $picking, onDismiss: {
            if wantsTransfer {
                wantsTransfer = false
                markingTransfer = true
            }
        }) {
            CategoryPicker(
                categories: categories,
                selected: filed ?? tx.categoryName,
                t: t,
                onPick: { id in
                /*
                 * Filing is not finishing.
                 *
                 * This closed the sheet, which put the one action the row was
                 * open for — "Vérifié" — behind reopening it. Categorising and
                 * approving are two halves of the same decision and belong in
                 * one visit, so the sheet stays and remembers what was just
                 * filed: the row it was handed cannot tell it, being a value
                 * from a list that has not refetched yet.
                 */
                    working = true
                    Task {
                        await onPatch(TxPatch(categoryId: .some(id)))
                        filed = categories.first { $0.id == id }?.name
                        working = false
                    }
                },
                // Outgoing rows only: the sheet it opens asks where the money
                // went, and the far end of an incoming one is a question it
                // does not know how to word.
                onTransfer: (!tx.isTransfer && tx.amount < 0 && accounts.count > 1)
                    ? { wantsTransfer = true }
                    : nil
            )
        }
        .sheet(isPresented: $filing) {
            ReviewCategorySheet(
                transactions: [tx],
                categories: categories,
                locale: locale,
                currency: currency,
                t: t,
                onAssign: { _, categoryId in
                    await onPatch(TxPatch(categoryId: .some(categoryId)))
                },
                onFinish: {
                    filing = false
                    run { await onPatch(TxPatch(approve: true)) }
                }
            )
        }
        /*
         * Saying it is a transfer, from the row itself.
         *
         * The app could only ever ask this on its own, from the dashboard's
         * "à rattacher" group — and that group only collects rows whose payee
         * matches a list of bank wordings and which carry no category. A
         * transfer the bank worded differently, or one the guesser had already
         * filed, fell outside both conditions and there was no way left to
         * say what it was: the review queue offers categories, and a category
         * is precisely the wrong answer for money that never left.
         */
        .sheet(isPresented: $markingTransfer) {
            AttachTransferSheet(
                transaction: tx,
                accounts: accounts,
                locale: locale,
                currency: currency,
                t: t,
                onAttach: { accountId in
                    await onAttachTransfer(accountId)
                    dismiss()
                },
                // Nothing to route to: the row is already spending, and the
                // button here means "leave it alone".
                onSpending: {}
            )
        }
        .sheet(isPresented: $naming) {
            MerchantNameSheet(
                key: MerchantNames.key(tx.payee),
                bankLabel: PayeeText.clean(tx.payee),
                t: t,
                categoryEmoji: tx.categoryEmoji
            )
        }
        .sheet(isPresented: $editing) {
            TransactionEditor(tx: tx, locale: locale, currency: currency, t: t) { patch in
                await onPatch(patch)
            }
        }
        /*
         * Une alerte, pas une feuille de confirmation.
         *
         * Depuis une feuille, iOS ancre un `confirmationDialog` sur ce qui l'a
         * déclenché et le dessine en bulle avec une flèche — un objet qui a
         * l'air d'un bug, et dont le bouton Annuler disparaît au passage : il
         * ne restait qu'un « Supprimer » rouge flottant au-dessus de l'écran.
         * Une alerte se centre, garde ses deux boutons, et se comporte pareil
         * partout — c'est déjà ce que la suppression d'un compte utilise.
         */
        .alert(
            t("v2.activity.deleteConfirm", "Supprimer cette opération ?"),
            isPresented: $confirmingDelete
        ) {
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                Task {
                    await onDelete()
                    dismiss()
                }
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(PayeeText.humanize(tx.payee))
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            AmountText(
                value: tx.amount, locale: locale, currency: currency,
                signed: true, tone: .auto, size: 40, weight: .light
            )

            Text(fullDate)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            // Wrapping, not a single scrolling row: three chips at 15pt run off
            // a 393pt screen the moment a category name is longer than "Courses".
            FlowRow(spacing: 8) {
                Pill(text: tx.accountName)
                Pill(
                    text: ((tx.categoryEmoji.map { $0 + " " } ?? "")
                        + (filed ?? tx.categoryName ?? t("v2.common.uncategorized", "Sans catégorie"))),
                    tone: (filed ?? tx.categoryName) == nil ? Florin.text3 : Florin.accent
                )
                if tx.needsReview {
                    Pill(text: t("v2.activity.needsReview", "À vérifier"), tone: Florin.negative)
                }
                if tx.isTransfer {
                    Pill(text: t("v2.activity.transfer", "Virement interne"))
                }
            }
            .padding(.horizontal, Florin.gutter)

            if let memo = tx.memo, !memo.isEmpty {
                Text(memo)
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Florin.gutter)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if tx.needsReview {
                SheetAction(
                    label: t("v2.review.approve", "Vérifié"),
                    symbol: "checkmark",
                    prominent: true
                ) {
                    // Nothing leaves the queue uncategorised without that being
                    // a decision. A transfer is the exception: it has no
                    // category by design.
                    if tx.categoryName == nil, filed == nil, !tx.isTransfer {
                        filing = true
                    } else {
                        run { await onPatch(TxPatch(approve: true)) }
                    }
                }
            }
            SheetAction(label: t("v2.review.categorize", "Catégoriser"), symbol: "tag") {
                picking = true
            }
            SheetAction(label: t("v2.common.edit", "Modifier"), symbol: "pencil") {
                editing = true
            }
            SheetAction(
                label: t("v2.common.delete", "Supprimer"),
                symbol: "trash",
                destructive: true
            ) {
                confirmingDelete = true
            }
        }
        .padding(.horizontal, Florin.gutter)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }

    private var fullDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f.string(from: tx.day)
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
            dismiss()
        }
    }
}

/// A full-width action in a sheet. Prominent is the one the screen is *for* —
/// on a review row that is "Vérifié", which is why it is the tinted one and the
/// destructive action is not.
struct SheetAction: View {
    let label: String
    let symbol: String
    var prominent = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(label).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(
                prominent ? Color.black : (destructive ? Florin.negative : Florin.text)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                prominent
                    ? AnyShapeStyle(Florin.accent)
                    : AnyShapeStyle(
                        destructive ? Florin.negative.opacity(0.12) : Florin.surface2
                    ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Chips that wrap. `Layout` rather than a wrapped `HStack` so a long category
/// name pushes the next chip down instead of off the screen.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((view, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            var cursor = bounds.minX + (bounds.width - rowWidth) / 2
            let height = row.map(\.1.height).max() ?? 0
            for (view, size) in row {
                view.place(
                    at: CGPoint(x: cursor, y: y + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                cursor += size.width + spacing
            }
            y += height + spacing
        }
    }
}


/// The measured height of a sheet's content, for sizing its detent.
/// Partagée : deux feuilles se dimensionnent maintenant sur leur contenu
/// plutôt que sur une constante.
struct SheetContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
