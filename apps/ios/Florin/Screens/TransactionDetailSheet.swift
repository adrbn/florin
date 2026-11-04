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
    /// Passed straight through to the edit sheet, which offers two rows only
    /// the device ledger can honour — see `AddTransactionSheet.isLocalLedger`.
    var isLocalLedger = false

    /// Ce que le grand livre propose pour cette ligne, s'il propose quelque chose.
    @State private var hints: [Category] = []

    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    /// The category chosen in this visit. The row this sheet was handed is a
    /// value from a list that has not refetched, so it still says "sans
    /// catégorie" a moment after one was assigned.
    @State private var filed: String?
    @State private var editing = false
    @State private var working = false
    @State private var filing = false
    @State private var markingTransfer = false
    /// Chosen inside the picker, acted on once the picker has closed: two
    /// sheets cannot change places in the same frame, and asking for the
    /// second one while the first is still dismissing silently drops it.
    @State private var wantsTransfer = false
    @State private var naming = false
    /// Le détail de la dépense, que seul le ticket connaît. Il était derrière
    /// un appui long sur la ligne — un geste que rien n'annonce.
    @State private var receipting = false
    /// Un ticket est posé sur cette opération : l'icône le dit en vert,
    /// autrement rien ne distingue « pas de ticket » de « pas regardé ».
    @State private var hasReceipt = false
    /// Le lien de remboursement, dans les deux sens — voir
    /// `LocalReimbursements`. Chargé à l'ouverture, relu après un changement.
    @State private var linking = false
    @State private var reimburses: LocalReimbursements.Entry?
    @State private var reimbursedBy: [LocalReimbursements.Entry] = []
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
        /*
         * Éditorial écrit plus grand, donc plus haut.
         *
         * Cette addition a été réglée sur la typographie d'Obsidienne. Le
         * même contenu en éditorial — montant plus gros, actions plus hautes
         * — dépasse d'une soixantaine de points, et la dernière action, la
         * rouge, se faisait couper par le bas de la feuille.
         */
        if FlorinPalette.selected == .editorial {
            height += 30 + CGFloat(actionCount) * 9
        }
        return min(height, 760)
    }

    /// Compte, catégorie, « à vérifier », « virement » — la rangée passe à deux
    /// lignes dès la troisième.
    private var pillRows: CGFloat {
        let pills = 2 + (tx.needsReview ? 1 : 0) + (tx.isTransfer ? 1 : 0)
        return pills > 2 ? 2 : 1
    }

    private var actionCount: Int {
        var n = 3   // modifier, catégoriser, supprimer
        if tx.needsReview { n += 1 }
        if !tx.isTransfer, tx.amount < 0, accounts.count > 1 { n += 1 }
        return n
    }

    /*
     * Deux habillages, une seule feuille — comme dans `AddTransactionSheet`,
     * et pour qu'elles se ressemblent enfin.
     */
    var body: some View {
        if editorial {
            plumbed(editorialShell)
        } else {
            plumbed(classicShell)
        }
    }

    private var classicShell: some View {
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
            .navigationTitle(PayeeText.title(tx.payee, category: tx.categoryName, plan: tx.instalmentPlanId))
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
                            Text(PayeeText.title(tx.payee, category: tx.categoryName, plan: tx.instalmentPlanId))
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
                /*
                 * Le ticket de caisse, en petit.
                 *
                 * Une rangée pleine largeur de plus le mettait au même rang
                 * que modifier ou supprimer, alors qu'il ne concerne qu'une
                 * dépense sur dix et qu'on n'y revient presque jamais. Une
                 * icône dans la barre se trouve quand on la cherche et ne pèse
                 * rien quand on ne la cherche pas.
                 */
                if isLocalLedger {
                    ToolbarItem(placement: .confirmationAction) {
                        /*
                         * Sans le verre du système.
                         *
                         * Un bouton de barre reçoit depuis iOS 26 une bulle de
                         * verre qui réfracte ce qu'il y a dessous : sur le
                         * dégradé de la feuille, l'appui en tirait une barre
                         * claire en travers de l'icône. Un glyphe nu n'a rien
                         * à réfracter, et discret est précisément ce qu'on lui
                         * demande.
                         */
                        Button { receipting = true } label: {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(hasReceipt ? Florin.positive : Florin.text2)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("v2.receipts.open", "Ticket de caisse"))
                    }
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
    }

    /*
     * Tout ce qui s'ouvre depuis cette feuille, écrit une fois.
     *
     * Six feuilles filles et un comptage de tickets : recopiés par habillage,
     * ils auraient été l'endroit exact où les deux versions se mettraient à
     * diverger sans que personne ne le voie.
     */
    private func plumbed(_ shell: some View) -> some View {
        shell
        .task { countReceipts() }
        .task { readLinks() }
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
                    : nil,
                hints: hints
            )
            // Lue à l'ouverture, pas à chaque redessin : elle relit le grand
            // livre, et le sélecteur se redessine à chaque lettre tapée.
            .task { hints = CategoryHint.categories(for: tx, in: categories) }
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
        .sheet(isPresented: $receipting) {
            ReceiptsSheet(
                tx: tx, locale: locale, currency: currency, t: t,
                onChanged: countReceipts
            )
        }
        .sheet(isPresented: $linking) {
            ReimbursementPicker(
                income: tx, t: t, locale: locale, currency: currency,
                linked: reimburses != nil, onPick: readLinks
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
        /*
         * The same sheet that created the row.
         *
         * It was a `Form` of four fields — and the row's account, its
         * category, its sign and its "en prévision" switch were all decided on
         * a screen this one did not resemble and could not undo.
         */
        .sheet(isPresented: $editing) {
            AddTransactionSheet(
                accounts: accounts,
                categories: categories,
                localeTag: locale,
                currency: currency,
                t: t,
                editing: tx,
                onPatch: { patch in
                    await onPatch(patch)
                    dismiss()
                },
                isLocalLedger: isLocalLedger
            )
        }
        /*
         * Plus de confirmation.
         *
         * Elle demandait un geste de plus à chaque suppression pour se
         * prémunir d'un accident rare — et d'un accident qui ne détruit rien :
         * la suppression est douce partout, la ligne reste dans la base.
         * Réparer vaut mieux que barrer la route, et c'est la corbeille des
         * Réglages qui répare (voir `LocalLedger.deletedRecently`).
         */
    }

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    // MARK: Éditorial

    /*
     * La coque de l'ajout, à l'identique.
     *
     * Celle-ci se présentait à sa hauteur exacte — ce qui, depuis iOS 26, la
     * dessine comme une carte flottante détachée des bords, pendant que la
     * feuille d'ajout, pleine hauteur, touche l'écran. Deux feuilles pour le
     * même objet, ouvertes l'une depuis l'autre, n'avaient donc ni la même
     * forme ni le même vocabulaire : un titre centré contre une pastille, un
     * montant centré contre un montant en héros, des faits en pastilles
     * contre des faits en rangées.
     *
     * Même bandeau, même héros, même carte de rangées, même action
     * principale en marge basse. Rien de neuf n'est dessiné : `RowGroup`,
     * `EdPill` et `SheetAction` sont ceux de partout, et `sheetHeight` ne
     * sert plus qu'à l'habillage classique.
     */
    private var editorialShell: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                edFigure
                edStatus
                edFacts
                edActions
                edPrimary
                edRefund
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { edHeader.background(Florin.bg) }
        .background(Florin.bg)
        /*
         * Elle s'arrête où le contenu s'arrête.
         *
         * Pleine hauteur, une opération ordinaire laissait la moitié de
         * l'écran en blanc sous le dernier bouton. UN SEUL cran, et pas de
         * `.large` à côté : c'est la paire de crans qui rend une feuille
         * redimensionnable, et une feuille redimensionnable est ce qu'iOS 26
         * dessine en carte flottante détachée des bords — le reproche de
         * départ. Avec un cran unique, elle garde les bords de l'écran.
         */
        .presentationDetents([.height(edSheetHeight)])
    }

    /*
     * La hauteur, additionnée plutôt que mesurée.
     *
     * Voir `sheetHeight` pour l'habillage classique, et pour la raison : une
     * hauteur MESURÉE sur la vue qu'elle dimensionne est une boucle, et elle
     * se stabilise au plafond. Le contenu est connu d'avance — un montant, un
     * nom, une date, trois rangées, deux actions puis une — donc on l'écrit.
     */
    private var edSheetHeight: CGFloat {
        var height: CGFloat = 58                       // bandeau
        height += 12 + edFigureSize * 1.2              // le montant
        height += 10 + 24 + 10 + 17 + 18               // nom, date
        if tx.needsReview || tx.isTransfer { height += 34 }
        height += 3 * 42 + 2                           // bénéficiaire, compte, catégorie

        if let memo = tx.memo, !memo.isEmpty {
            height += 24 + CGFloat(min(4, memo.count / 38 + 1)) * 18
        }
        height += 18 + 68                              // la rangée de trois
        height += 10 + 62                              // l'action principale
        if reimbursementRow { height += 18 + 34 }      // la note de remboursement
        height += 28 + 16                              // marge basse et poignée
        return min(height, 760)
    }

    private var edHeader: some View {
        HStack(spacing: 2) {
            EdPill(text: t("v2.activity.title", "Activité"))
            Spacer(minLength: 8)
            if isLocalLedger {
                EdIconButton(
                    symbol: hasReceipt ? "doc.text.image" : "doc.text.viewfinder",
                    label: t("v2.receipts.open", "Ticket de caisse")
                ) { receipting = true }
            }
        }
        /*
         * Pas d'entrée en scène dans une marge sûre.
         *
         * `EdPill` et `EdIconButton` fondent en arrivant, et cette fonte est
         * une `scrollTransition` : elle attend du défilement qu'il lui rende
         * une phase d'identité. Un `safeAreaInset` vit HORS du défilement —
         * la phase ne revenait donc jamais, et cent cinquante millisecondes
         * après l'ouverture le bandeau entier passait à zéro. Il gardait sa
         * place, d'où une feuille qui s'ouvrait sur cinquante points de blanc
         * sans nom et sans croix pour la fermer.
         */
        .environment(\.edEnterApplied, true)
        .padding(.horizontal, Ed.gutter)
        .padding(.trailing, -10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Le montant est le sujet de la feuille : il s'écrit à la taille d'un
    /// titre, et il porte la couleur de son sens — comme dans l'ajout, d'où
    /// l'on arrive.
    private var edFigure: some View {
        AmountText(
            value: tx.amount, locale: locale, currency: currency,
            signed: true, tone: .auto, size: edFigureSize, weight: .medium
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 12)
    }

    /// Il descend quand il s'allonge : un montant tronqué est un montant faux.
    private var edFigureSize: CGFloat {
        switch Money.string(tx.amount, locale: locale, currency: currency, signed: true).count {
        case ...9: return 72
        case 10, 11: return 56
        default: return 42
        }
    }

    /// Le nom du marchand, la date, puis ce qui cloche s'il y a lieu. Une
    /// opération ordinaire n'affiche aucune pastille : elles sont là pour les
    /// exceptions, pas pour meubler.
    private var edStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PayeeText.title(tx.payee, category: tx.categoryName, plan: tx.instalmentPlanId))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Florin.text)
                .lineLimit(2)

            Text(fullDate)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            if tx.needsReview || tx.isTransfer {
                HStack(spacing: 8) {
                    if tx.needsReview {
                        EdPill(
                            text: t("v2.activity.needsReview", "À vérifier"),
                            tone: Florin.negative
                        )
                    }
                    if tx.isTransfer {
                        EdPill(text: t("v2.activity.transfer", "Virement interne"))
                    }
                }
            }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    /*
     * « Bénéficiaire » ne vaut que pour un virement.
     *
     * Le mot vient du formulaire de virement de la banque, où il est juste :
     * quelqu'un reçoit. Posé sur une dépense, il nomme mal ce qu'on lit —
     * une boulangerie n'est pas bénéficiaire d'un pain, elle le vend ; et sur
     * une rentrée il est carrément à l'envers, puisque le bénéficiaire, c'est
     * soi. Trois natures, trois mots, décidés par la ligne elle-même.
     */
    private var payeeLabel: String {
        if tx.isTransfer { return t("v2.add.payee", "Bénéficiaire") }
        return tx.amount > 0
            ? t("v2.detail.source", "Provenance")
            : t("v2.detail.merchant", "Commerçant")
    }

    /// Les faits, dans la carte de rangées de l'ajout — bénéficiaire, compte,
    /// catégorie, note — et dans le même ordre, pour que passer de la lecture
    /// à la modification ne déplace rien sous le pouce.
    private var edFacts: some View {
        RowGroup {
            edFact(
                symbol: "person.crop.circle", label: payeeLabel,
                value: PayeeText.title(tx.payee, category: tx.categoryName, plan: tx.instalmentPlanId),
                tap: { naming = true }
            )
            Hairline()
            edFact(
                symbol: "building.columns", label: t("v2.add.account", "Compte"),
                value: tx.accountName, tap: nil
            )
            Hairline()
            edFact(
                symbol: "tag", label: t("v2.add.category", "Catégorie"),
                value: EdSymbols.label(
                    tx.categoryEmoji,
                    filed ?? tx.categoryName ?? t("v2.common.uncategorized", "Sans catégorie")
                ),
                tap: { picking = true }
            )

            if let memo = tx.memo, !memo.isEmpty {
                Hairline()
                HStack(alignment: .top, spacing: 13) {
                    RowIcon("text.alignleft")
                    Text(memo)
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, Florin.gutter)
    }

    /*
     * Une rangée de fait, qui se touche ou non.
     *
     * Même anatomie que `pickerRow` dans l'ajout : l'icône, le mot en gris,
     * la valeur en pastille à droite. Sans geste, la pastille perd son
     * contour — un cadre qui ne mène nulle part est une promesse non tenue.
     */
    private func edFact(
        symbol: String, label: String, value: String, tap: (() -> Void)?
    ) -> some View {
        HStack(spacing: 13) {
            RowIcon(symbol)
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 10)
            if let tap {
                Button(action: tap) { edValue(value, tappable: true) }
                    .buttonStyle(.plain)
            } else {
                edValue(value, tappable: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Une rentrée propose toujours de désigner sa dépense ; une dépense ne
    /// dit quelque chose que si on lui a rendu de l'argent.
    /*
     * Ce qu'on vous a rendu — une note, pas un fait.
     *
     * C'était une rangée de plus sous Bénéficiaire, Compte et Catégorie,
     * c'est-à-dire au même rang que les trois choses qu'une opération EST.
     * Un remboursement n'en est pas une : il en relie deux, il arrive après,
     * et souvent il n'y en a pas. Au même niveau, il faisait lire la liste
     * comme si l'app ne savait pas ce qui comptait.
     *
     * Il descend donc sous l'action principale, en une ligne discrète avec
     * sa flèche de retour — la place d'une annotation. Ce qu'il dit change
     * de sens selon le côté : une rentrée désigne SA dépense (et se tape
     * pour la choisir), une dépense récite ce qui lui est revenu.
     */
    @ViewBuilder
    private var edRefund: some View {
        if reimbursementRow {
            let tappable = tx.amount > 0
            Button {
                guard tappable else { return }
                linking = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Florin.text3)
                    Text(tx.amount > 0
                        ? t("v2.detail.reimburses", "Remboursement de")
                        : t("v2.detail.reimbursed", "Remboursé"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text3)
                    Text(reimbursementValue)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(reimburses == nil && tappable ? Florin.accent : Florin.text2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!tappable)
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 18)
        }
    }

    private var reimbursementRow: Bool {
        guard !tx.isTransfer, !tx.isMovementOnly else { return false }
        return tx.amount > 0 ? true : !reimbursedBy.isEmpty
    }

    private var reimbursementValue: String {
        if tx.amount > 0 {
            guard let reimburses else { return t("v2.detail.linkExpense", "Lier une dépense") }
            return PayeeText.title(reimburses.payee, category: nil)
        }
        let back = reimbursedBy.reduce(0) { $0 + $1.amount }
        return t("v2.detail.reimbursedOf", "{back} sur {total}", [
            "back": Money.string(back, locale: locale, currency: currency),
            "total": Money.string(abs(tx.amount), locale: locale, currency: currency),
        ])
    }

    private func readLinks() {
        guard let store = LocalStore.shared else { return }
        reimbursedBy = (try? LocalReimbursements.on(store: store, expense: tx.id)) ?? []
        reimburses = try? LocalReimbursements.linked(store: store, income: tx.id)
    }

    private func edValue(_ text: String, tappable: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Florin.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, tappable ? 11 : 0)
            .padding(.vertical, tappable ? 6 : 0)
            .overlay {
                if tappable { Capsule().strokeBorder(Florin.text.opacity(0.28), lineWidth: 1) }
            }
            .frame(maxWidth: 200, alignment: .trailing)
    }

    /*
     * L'action pour laquelle on a ouvert la fiche, sous les autres.
     *
     * Sur une ligne à vérifier c'est « Vérifié » ; sur les autres,
     * « Modifier ». Elle était épinglée en marge basse, comme « Enregistrer »
     * dans l'ajout — mais l'ajout a un clavier qui pousse sa marge, et une
     * fiche n'en a pas : sur une opération ordinaire, c'était six cents points
     * de blanc entre la dernière rangée et le bouton. Elle suit donc le
     * contenu, et la feuille s'arrête où le contenu s'arrête.
     */
    private var edPrimary: some View {
        Group {
            if tx.needsReview {
                SheetAction(
                    label: t("v2.review.approve", "Vérifié"), symbol: "checkmark",
                    prominent: true, large: true
                ) {
                    if tx.categoryName == nil, filed == nil, !tx.isTransfer {
                        filing = true
                    } else {
                        run { await onPatch(TxPatch(approve: true)) }
                    }
                }
            } else {
                SheetAction(
                    label: t("v2.common.edit", "Modifier"), symbol: "pencil",
                    prominent: true, large: true
                ) { editing = true }
            }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 10)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }

    /*
     * Le reste, côte à côte.
     *
     * Trois rangées pleine largeur empilées, c'est cent quatre-vingts points
     * pour trois mots — et une feuille qui descend jusqu'en bas de l'écran
     * pour des gestes rares. Ils tiennent la même ligne : le symbole au-dessus
     * du mot, trois colonnes égales, et la hauteur de la feuille retombe de
     * moitié. Seule l'action principale garde sa pleine largeur, parce qu'elle
     * est la seule qu'on vienne chercher.
     */
    private var edActions: some View {
        HStack(spacing: 10) {
            if tx.needsReview {
                edSmallAction(t("v2.common.edit", "Modifier"), "pencil") { editing = true }
            }
            edSmallAction(t("v2.review.categorize", "Catégoriser"), "tag") { picking = true }
            edSmallAction(
                t("v2.common.delete", "Supprimer"), "trash", destructive: true
            ) {
                Task {
                    await onDelete()
                    dismiss()
                }
            }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 18)
        .disabled(working)
        .opacity(working ? 0.5 : 1)
    }

    /// Une colonne de la rangée. Le contour d'un bouton secondaire éditorial,
    /// en vertical — « Catégoriser » ne tient pas à côté de son symbole sur un
    /// tiers d'écran.
    private func edSmallAction(
        _ label: String, _ symbol: String, destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let tint = destructive ? Florin.negative : Florin.text
        return Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                editorial ? Color.clear : tint.opacity(destructive ? 0.12 : 0.08),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                if editorial {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        VStack(spacing: 12) {
            AmountText(
                value: tx.amount, locale: locale, currency: currency,
                signed: true, tone: editorial ? .neutral : .auto,
                size: editorial ? 56 : 40, weight: editorial ? .medium : .light
            )

            Text(fullDate)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)

            // Wrapping, not a single scrolling row: three chips at 15pt run off
            // a 393pt screen the moment a category name is longer than "Courses".
            FlowRow(spacing: 8) {
                Pill(text: tx.accountName)
                Pill(
                    text: EdSymbols.label(
                        tx.categoryEmoji,
                        filed ?? tx.categoryName
                            ?? t("v2.common.uncategorized", "Sans catégorie")
                    ),
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
            SheetAction(label: t("v2.common.edit", "Modifier"), symbol: "pencil") {
                editing = true
            }
            SheetAction(label: t("v2.review.categorize", "Catégoriser"), symbol: "tag") {
                picking = true
            }
            SheetAction(
                label: t("v2.common.delete", "Supprimer"),
                symbol: "trash",
                destructive: true
            ) {
                Task {
                    await onDelete()
                    dismiss()
                }
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

    private func countReceipts() {
        guard let store = LocalStore.shared else { return }
        hasReceipt = ((try? LocalReceipts.count(store: store, transactionId: tx.id)) ?? 0) > 0
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
    /// L'action principale d'une feuille éditoriale, où elle est seule sur sa
    /// ligne : elle a la place d'être plus grande que ce qui l'entoure.
    var large = false
    let action: () -> Void

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    /// Capsule en éditorial, coin arrondi ailleurs. Un rayon de 28 sur un
    /// bouton de 50 points de haut EST une capsule — le rayon se borne à la
    /// moitié de la hauteur — donc une seule forme suffit aux deux styles.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: editorial ? 28 : 16, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: large ? 18 : 15, weight: .semibold))
                Text(label).font(.system(size: large ? 19 : 16, weight: .semibold))
            }
            /*
             * Noir sur l'accent était faux en clair.
             *
             * L'accent est soutenu en mode clair et porte du blanc ; le noir
             * écrit en dur datait d'une app qui n'avait qu'une face. `onAccent`
             * est le jeton qui sait lequel des deux va dessus.
             */
            .foregroundStyle(
                prominent
                    ? Florin.onAccent
                    : (destructive ? Florin.negative : Florin.text)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, large ? 20 : 15)
            /*
             * En éditorial, un bouton secondaire est un contour.
             *
             * Le gris plein de `surface2` est justement ce que la maquette
             * refuse : elle ne remplit que l'action principale, et laisse les
             * autres se tenir dans un trait d'un point. Le destructif garde sa
             * couleur — c'est une information, pas une décoration.
             */
            .background(
                prominent
                    ? AnyShapeStyle(Florin.accent)
                    : AnyShapeStyle(
                        editorial
                            ? Color.clear
                            : (destructive ? Florin.negative.opacity(0.12) : Florin.surface2)
                    ),
                in: shape
            )
            .overlay {
                if editorial, !prominent {
                    shape.strokeBorder(
                        (destructive ? Florin.negative : Florin.text).opacity(0.28),
                        lineWidth: 1
                    )
                }
            }
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
