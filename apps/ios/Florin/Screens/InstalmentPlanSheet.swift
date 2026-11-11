import SwiftUI

/*
 * Un achat en plusieurs fois, vu comme un achat.
 *
 * L'écran listait les échéances à plat : quatre lignes à un mois d'intervalle,
 * et celles de deux achats différents mêlées au même niveau, si bien qu'un
 * voyage et un flacon de parfum se répondaient en alternance. Le pli disait
 * « 10 opérations » — ce qui est vrai de la base et faux de la vie : il y avait
 * trois achats.
 *
 * Une ligne par échéancier, donc, et le détail derrière. La ligne répond à ce
 * qu'on se demande en passant — chez qui, combien il reste, quand tombe la
 * prochaine — et la sheet à ce qu'on vient vérifier : le prix d'achat, les
 * frais s'il y en a, chaque échéance avec sa date et son sort.
 */
struct InstalmentPlanRow: View {
    let plan: LocalInstalments.Schedule
    let locale: String
    let currency: String
    var t: Strings = .empty

    /// Observés pour la même raison que dans `TransactionRowView` : une
    /// enseigne renommée depuis sa fiche se renomme ici sans rechargement.
    @ObservedObject private var names = MerchantNames.shared
    @ObservedObject private var logos = MerchantLogos.shared

    private var title: String { PayeeText.title(plan.payee, category: plan.categoryName, plan: plan.id) }

    var body: some View {
        HStack(spacing: 12) {
            let face = logos.face(for: plan.payee, plan: plan.id)
            Bubble(
                label: plan.categoryName ?? plan.payee,
                name: plan.payee,
                chosen: face?.emoji,
                emoji: plan.categoryEmoji,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                // Soldé, « 0,00 € » ne dit rien : ce qu'on relit alors, c'est
                // ce que l'achat a coûté en tout.
                AmountText(
                    value: plan.isOver ? plan.total : plan.remaining,
                    locale: locale, currency: currency,
                    tone: plan.isOver ? .muted : .neutral
                )
                InstalmentProgress(count: plan.count, paid: plan.paidCount)
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Où en est l'échéancier, et quand tombe la suite. Le nombre payé passe
    /// avant la date parce que c'est lui qui dit si l'achat est derrière soi.
    private var subtitle: String {
        let progress = t(
            "v2.instalments.paidOf", "{paid} sur {count} payées",
            ["paid": plan.paidCount, "count": plan.count]
        )
        guard let next = plan.next else { return progress }
        return progress + " · " + DayLabel.string(next.day, locale: locale, t: t)
    }
}

/*
 * Où en est l'échéancier, sans chiffre.
 *
 * Des pastilles tant qu'on peut les compter d'un coup d'œil — quatre
 * remplies sur six se lisent sans lire — et une barre au-delà, où elles ne
 * seraient plus qu'un damier. Dix échéances ne se comptent pas à la pastille.
 */
struct InstalmentProgress: View {
    let count: Int
    let paid: Int
    var width: CGFloat = 54

    private var fraction: Double {
        guard count > 0 else { return 0 }
        return min(1, max(0, Double(paid) / Double(count)))
    }

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    var body: some View {
        /*
         * En éditorial, un seul filet, et il fait la largeur du montant.
         *
         * Les pastilles sont justes dans Obsidienne, où l'accent violet est
         * une couleur de l'écran. Ici elles étaient la seule chose colorée de
         * la colonne, et leurs 54 points pendaient sous une pastille de
         * montant deux fois plus large — un trait qui ne s'aligne sur rien se
         * lit comme un défaut, pas comme une mesure. La ligne « 2 sur 4
         * payées » dit déjà le compte ; le filet n'a qu'à en donner la part,
         * et il la donne mieux aligné sous le chiffre qu'il commente.
         */
        if editorial {
            /*
             * Un trait par échéance, et une largeur qui ne dépend de rien.
             *
             * Deux défauts tenaient au même choix. Le filet continu donnait
             * une proportion — un tiers, la moitié — là où la question est
             * « combien sur combien » : trois échéances sur quatre, ce n'est
             * pas 75 % d'un achat, c'est un trait qui reste. Et sa largeur
             * `maxWidth: .infinity` était celle de la colonne, donc celle de
             * la pastille de montant au-dessus : « −9 € » et « −90,96 € » ne
             * font pas la même largeur, si bien que le filet de chaque ligne
             * démarrait à une abscisse différente et qu'aucun ne se comparait
             * à son voisin. Une largeur fixe les aligne tous.
             */
            HStack(spacing: 3) {
                ForEach(0..<max(1, count), id: \.self) { index in
                    Capsule()
                        .fill(index < paid ? Florin.text : Florin.text.opacity(0.16))
                        .frame(height: 2)
                }
            }
            .frame(width: width)
        } else if count <= 6 {
            HStack(spacing: 3) {
                ForEach(0..<max(1, count), id: \.self) { index in
                    Capsule()
                        .fill(index < paid ? Florin.accent : Florin.text.opacity(0.14))
                        .frame(height: 3)
                }
            }
            .frame(width: width)
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(Florin.text.opacity(0.14))
                Capsule().fill(Florin.accent).frame(width: width * fraction)
            }
            .frame(width: width, height: 3)
        }
    }
}

// MARK: - Le détail

struct InstalmentPlanSheet: View {
    let plan: LocalInstalments.Schedule
    let locale: String
    let currency: String
    let t: Strings
    /// Une échéance prélevée a été touchée. L'appelant ferme cette feuille
    /// puis ouvre la fiche : voir `openTapped`.
    var onOpen: ((Transaction) -> Void)?
    /// Appelé quand l'échéancier vient d'être oublié : la page dessous ne
    /// sait pas toute seule qu'elle a une ligne de moins.
    var onForget: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var logos = MerchantLogos.shared
    @State private var confirming = false
    @State private var renaming = false

    private var title: String { PayeeText.title(plan.payee, category: plan.categoryName, plan: plan.id) }

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    /*
     * Une échéance prélevée EST une opération, et s'ouvre.
     *
     * Elle porte le même identifiant que la ligne de la banque ; il n'y a donc
     * rien à retrouver. Ce qui manquait n'était pas la donnée mais le geste :
     * une ligne « Prélevée » était un cul-de-sac là où tout le reste s'ouvre.
     *
     * Deux feuilles dans la même image, SwiftUI en escamote une : on ferme
     * d'abord, et c'est l'appelant qui ouvre la fiche une fois celle-ci
     * refermée. Une échéance « Prévu » reste fermée — c'est une prévision,
     * pas une opération, et sa fiche parlerait d'autre chose.
     */
    private func openTapped(_ tx: Transaction) {
        guard !tx.isScheduled, let onOpen else { return }
        dismiss()
        onOpen(tx)
    }

    private func opens(_ tx: Transaction) -> Bool { !tx.isScheduled && onOpen != nil }

    var body: some View {
        Group {
            if editorial { editorialShell } else { classicShell }
        }
        /*
         * Renommer l'ACHAT, pas le rail.
         *
         * Le relevé d'un 4x ne porte que « PAYPAL *Paieme » : le même libellé,
         * donc la même clé, pour toutes les boutiques du monde. Renommer ce
         * marchand-là nommerait les quatre échéanciers en cours d'un coup.
         * L'achat porte sa propre clé — `MerchantNames.planKey` — et son nom,
         * comme sa tête, ne vaut que pour ses lignes à lui.
         */
        .sheet(isPresented: $renaming) {
            MerchantNameSheet(
                key: MerchantNames.planKey(plan.id),
                bankLabel: plan.payee, t: t,
                categoryEmoji: plan.categoryEmoji,
                title: t("v2.instalments.rename", "Renommer cet achat"),
                reach: t(
                    "v2.merchant.reachPlan",
                    "S'applique aux {count} échéances de cet achat, et à elles seules. Les autres opérations de ce bénéficiaire gardent leur nom.",
                    ["count": plan.count]
                )
            )
        }
    }


    /*
     * La même coque que la fiche d'une opération.
     *
     * Un échéancier est un achat, et on l'ouvre depuis la même liste que les
     * opérations : lui donner une barre de navigation, un fond teinté et une
     * feuille pleine hauteur, c'était changer de maison en changeant de
     * ligne. Il reprend donc la coque éditoriale — bandeau en pastille,
     * chiffre en grand, faits en rangées, action en bas — et s'arrête où son
     * contenu s'arrête.
     */
    private var editorialShell: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                edFigure
                edStatus
                edFacts
                edSchedule
                edPrimary
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { edHeader.background(Florin.bg) }
        .background(Florin.bg)
        .presentationDetents([.height(edSheetHeight)])
        .confirmationDialog(
            t("v2.instalments.forget", "Supprimer l'échéancier"),
            isPresented: $confirming, titleVisibility: .visible
        ) { forgetButtons } message: { forgetMessage }
    }

    private var classicShell: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.activity.tint).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summary
                        schedule
                        forget
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.vertical, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(t("v2.instalments.planTitle", "Paiement en plusieurs fois"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - La coque éditoriale

    /// Voir `TransactionDetailSheet.edHeader` : une fonte d'entrée dans une
    /// marge sûre n'a pas de défilement pour lui rendre sa phase d'identité.
    /// Pas de croix non plus — la feuille se ferme en la tirant vers le bas.
    private var edHeader: some View {
        HStack(spacing: 2) {
            EdPill(text: t("v2.instalments.planTitle", "Paiement en plusieurs fois"))
            Spacer(minLength: 8)
        }
        .environment(\.edEnterApplied, true)
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Ce qu'il reste à payer : la seule question qu'on se pose en ouvrant un
    /// échéancier en cours. Soldé, c'est le prix d'achat qui prend la place,
    /// parce qu'un zéro en gros corps ne dit rien de l'achat qu'on relit.
    private var edFigure: some View {
        AmountText(
            value: plan.isOver ? -plan.purchase : -plan.remaining,
            locale: locale, currency: currency,
            signed: true, tone: .auto, size: edFigureSize, weight: .medium
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 12)
    }

    /// Il descend quand il s'allonge : un montant tronqué est un montant faux.
    private var edFigureSize: CGFloat {
        let shown = plan.isOver ? plan.purchase : plan.remaining
        switch Money.string(-shown, locale: locale, currency: currency, signed: true).count {
        case ...9: return 72
        case 10, 11: return 56
        default: return 42
        }
    }

    private var edStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { renaming = true } label: {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Florin.text3)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Text(edCaption)
                    .font(.system(size: 14))
                    .foregroundStyle(Florin.text2)
                    .lineLimit(1)
                InstalmentProgress(count: plan.count, paid: plan.paidCount)
                    .hiddenWhenPrivate()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 10)
    }

    /// « Reste à payer · 2/4 » — le chiffre au-dessus a besoin qu'on dise ce
    /// qu'il est, et l'avancement tient en deux nombres.
    private var edCaption: String {
        let what = plan.isOver
            ? t("v2.instalments.purchase", "Montant de l'achat")
            : t("v2.instalments.remainingTotal", "Reste à payer")
        return what + " · \(plan.paidCount)/\(plan.count)"
    }

    private var edFacts: some View {
        RowGroup {
            edFact(t("v2.instalments.purchase", "Montant de l'achat"), Money.string(
                plan.purchase, locale: locale, currency: currency
            ))
            Hairline()
            edFact(t("v2.add.instalmentsFees", "Frais"), edFees)
            Hairline()
            edFact(t("v2.instalments.paidTotal", "Déjà payé"), Money.string(
                plan.paid, locale: locale, currency: currency
            ))
            Hairline()
            edFact(t("v2.add.account", "Compte"), plan.accountName)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 18)
    }

    /// Sans frais, on le dit en toutes lettres. Avec, le taux annuel suit le
    /// montant, parce que c'est lui qui dit ce que l'offre coûte vraiment.
    private var edFees: String {
        guard !plan.isFree else { return t("v2.add.instalmentsNoFees", "Sans frais") }
        let amount = Money.string(plan.fees, locale: locale, currency: currency)
        guard let rate = plan.annualRate, rate > 0 else { return amount }
        return amount + " · " + t("v2.add.instalmentsPerYear", "{rate} par an",
                                  ["rate": Money.percent(rate, locale: locale)])
    }

    private func edFact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 13) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 210, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var edSchedule: some View {
        VStack(alignment: .leading, spacing: 0) {
            EdSection(text: t("v2.instalments.schedule", "Échéances"))
                .padding(.horizontal, Ed.gutter)
                .padding(.top, 22)
                .padding(.bottom, 8)
            RowGroup {
                ForEach(Array(plan.instalments.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 { Hairline() }
                    if opens(tx) {
                        Button { openTapped(tx) } label: { edStep(tx, rank: index + 1) }
                            .buttonStyle(.plain)
                    } else {
                        edStep(tx, rank: index + 1)
                    }
                }
            }
            .padding(.horizontal, Ed.gutter)
        }
    }

    /*
     * Une échéance : son rang, sa date, son sort, son montant.
     *
     * Pas de fond teinté sur la prochaine — l'éditorial n'a pas de couleur à
     * dépenser pour ça. C'est l'encre pleine qui la désigne, et le gris qui
     * efface celles qui sont derrière.
     */
    private func edStep(_ tx: Transaction, rank: Int) -> some View {
        let isNext = tx.id == plan.next?.id
        return HStack(spacing: 12) {
            Text("\(rank)/\(plan.count)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tx.isScheduled ? Florin.text2 : Florin.text3)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.string(tx.day, locale: locale, t: t))
                    .font(.system(size: 15, weight: isNext ? .semibold : .medium))
                    .foregroundStyle(tx.isScheduled ? Florin.text : Florin.text2)
                    .lineLimit(1)
                Text(
                    tx.isScheduled
                        ? t("v2.activity.scheduled", "Prévu")
                        : t("v2.instalments.settled", "Prélevée")
                )
                .font(.system(size: 12))
                .foregroundStyle(Florin.text3)
            }
            Spacer(minLength: 8)
            EdAmountPill(
                text: Money.string(
                    -abs(tx.amount), locale: locale, currency: currency, signed: true
                ),
                tone: tx.isScheduled ? EdMoney.minus : Florin.text3
            )
            if opens(tx) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private var edPrimary: some View {
        SheetAction(
            label: t("v2.instalments.forget", "Supprimer l'échéancier"),
            symbol: "trash", destructive: true, large: true
        ) { confirming = true }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 22)
    }

    @ViewBuilder
    private var forgetButtons: some View {
        Button(t("v2.common.delete", "Supprimer"), role: .destructive) { forgetPlan(expecting: false) }
        /*
         * On supprime un échéancier parce qu'on se fait rembourser.
         *
         * Pas « lier » : au moment où l'on supprime, le crédit n'est pas
         * arrivé, il n'y a rien à lier. Ce qui existe, c'est l'attente — la
         * même qu'une fiche de dépense propose — et elle porte ici la somme
         * de ce qui a DÉJÀ été prélevé, puisque c'est tout ce qu'on peut se
         * faire rendre.
         *
         * Proposé, jamais fait d'office : on supprime aussi un échéancier
         * parce qu'on l'a mal saisi, et une attente de plus serait alors une
         * rentrée qui n'arrivera pas.
         */
        if plan.paidCount > 0, plan.accountId != nil {
            Button(
                t("v2.instalments.forgetAndExpect", "Supprimer et attendre {amount}", [
                    "amount": Money.string(
                        abs(plan.paid), locale: locale, currency: currency
                    ),
                ]),
                role: .destructive
            ) { forgetPlan(expecting: true) }
        }
        Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
    }

    private func forgetPlan(expecting: Bool) {
        // Écriture d'abord : une suppression qui échoue ne doit pas
        // refermer la feuille en disant que c'est fait.
        guard let store = LocalStore.shared,
              (try? LocalInstalments.forget(store: store, planId: plan.id)) != nil
        else { return }
        if expecting, let accountId = plan.accountId {
            try? LocalWallet.recordRefund(
                store: store, accountId: accountId, amount: abs(plan.paid),
                payee: plan.payee, categoryId: plan.instalments.first?.categoryId
            )
        }
        onForget?()
        dismiss()
    }

    private var forgetMessage: some View {
        Text(
            plan.paidCount == 0
                ? t("v2.instalments.forgetAll", "Ses {count} échéances partent à la corbeille.",
                    ["count": plan.count])
                : t("v2.instalments.forgetSome",
                    "Ses {due} échéances à venir partent à la corbeille. Les {paid} déjà prélevées restent, comme dépenses ordinaires.",
                    ["due": plan.due.count, "paid": plan.paidCount])
        )
    }

    /*
     * La hauteur, additionnée à la main.
     *
     * Mesurer la vue dont on fixe la hauteur est une boucle — c'est
     * exactement ce qui a gonflé les volets de l'Activité. On additionne donc
     * ce qu'on pose, et un échéancier long s'arrête au plafond et défile.
     */
    private var edSheetHeight: CGFloat {
        var height: CGFloat = 58
        height += 12 + edFigureSize * 1.2
        height += 10 + 24 + 4 + 18
        height += 18 + 4 * 42 + 3
        height += 22 + 24 + 8
        height += CGFloat(plan.count) * 56 + CGFloat(max(0, plan.count - 1))
        height += 22 + 62
        height += 28 + 16
        return min(height, 780)
    }

    /*
     * Défaire un achat qu'on n'aurait pas dû saisir.
     *
     * En bas, et en rouge seulement sur le mot : c'est la seule sortie d'un
     * échéancier saisi en double, mais ce n'est pas ce qu'on vient faire ici.
     *
     * Le texte de la confirmation dit les deux moitiés, parce qu'elles n'ont
     * pas le même poids : les échéances à venir partent à la corbeille, celles
     * que la banque a déjà prélevées restent — c'est de l'argent sorti, il ne
     * disparaît pas parce qu'on oublie le plan qui l'expliquait.
     */
    private var forget: some View {
        Button(role: .destructive) {
            confirming = true
        } label: {
            Text(t("v2.instalments.forget", "Supprimer l'échéancier"))
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Florin.negative.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        }
        .tint(Florin.negative)
        .confirmationDialog(
            t("v2.instalments.forget", "Supprimer l'échéancier"),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                guard let store = LocalStore.shared,
                      (try? LocalInstalments.forget(store: store, planId: plan.id)) != nil
                else { return }
                onForget?()
                dismiss()
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(
                plan.paidCount == 0
                    ? t("v2.instalments.forgetAll", "Ses {count} échéances partent à la corbeille.",
                        ["count": plan.count])
                    : t("v2.instalments.forgetSome",
                        "Ses {due} échéances à venir partent à la corbeille. Les {paid} déjà prélevées restent, comme dépenses ordinaires.",
                        ["due": plan.due.count, "paid": plan.paidCount])
            )
        }
    }

    // MARK: -

    private var header: some View {
        HStack(spacing: 14) {
            let face = logos.face(for: plan.payee, plan: plan.id)
            Bubble(
                label: plan.categoryName ?? plan.payee,
                name: plan.payee,
                chosen: face?.emoji,
                emoji: plan.categoryEmoji,
                size: 52,
                logo: face?.logo
            )
            VStack(alignment: .leading, spacing: 4) {
                Button { renaming = true } label: {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                Text(
                    t("v2.instalments.paidOf", "{paid} sur {count} payées",
                      ["paid": plan.paidCount, "count": plan.count])
                    + " · " + plan.accountName
                )
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /*
     * Ce que l'achat a coûté, et ce qu'il reste à en payer.
     *
     * Le prix d'achat figure en premier parce que c'est lui qu'on reconnaît —
     * le ticket, le panier — et les frais juste après, puisque la seule chose
     * qu'on cherche à savoir d'une facilité de paiement est si elle en a. Sans
     * frais, le taux annuel n'a rien à dire et ne s'affiche pas ; avec, il
     * dit ce que l'offre coûte vraiment (voir `LocalInstalments.annualRate`).
     */
    private var summary: some View {
        RowGroup {
            line(t("v2.instalments.purchase", "Montant de l'achat"), plan.purchase)
            Hairline()
            HStack {
                Text(t("v2.add.instalmentsFees", "Frais"))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 8)
                if plan.isFree {
                    SettingsValue(text: t("v2.add.instalmentsNoFees", "Sans frais"))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        let rate = plan.annualRate
                        AmountText(
                            value: plan.fees, locale: locale, currency: currency,
                            // Rouge au-delà de dix pour cent, comme dans la
                            // sheet d'ajout : à ce niveau ce n'est plus une
                            // facilité de caisse mais un crédit.
                            tone: (rate ?? 0) > 0.10 ? .negative : .neutral
                        )
                        if let rate, rate > 0 {
                            Text(t("v2.add.instalmentsPerYear", "{rate} par an",
                                   ["rate": Money.percent(rate, locale: locale)]))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.text3)
                        }
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 12)
            Hairline()
            line(t("v2.instalments.paidTotal", "Déjà payé"), plan.paid)
            Hairline()
            line(
                t("v2.instalments.remainingTotal", "Reste à payer"), plan.remaining,
                tone: plan.isOver ? .muted : .neutral, strong: !plan.isOver
            )
        }
    }

    private func line(
        _ label: String, _ value: Double,
        tone: AmountText.Tone = .neutral, strong: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text)
            Spacer(minLength: 8)
            AmountText(
                value: value, locale: locale, currency: currency, tone: tone,
                weight: strong ? .semibold : .medium
            )
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
    }

    /*
     * L'échéancier, dans l'ordre où il tombe.
     *
     * Chaque ligne porte son rang — « 2 / 4 » — parce que c'est ainsi qu'une
     * offre en parle, et son sort : prélevée, ou à venir. La prochaine est
     * mise en avant, les passées s'effacent : on ne relit pas une échéance
     * payée, on vérifie celle qui vient.
     */
    private var schedule: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.instalments.schedule", "Échéances"))
            RowGroup {
                ForEach(Array(plan.instalments.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 { Hairline() }
                    if opens(tx) {
                        Button { openTapped(tx) } label: { step(tx, rank: index + 1) }
                            .buttonStyle(.plain)
                    } else {
                        step(tx, rank: index + 1)
                    }
                }
            }
        }
    }

    private func step(_ tx: Transaction, rank: Int) -> some View {
        let isNext = tx.id == plan.next?.id
        return HStack(spacing: 12) {
            Text("\(rank) / \(plan.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tx.isScheduled ? Florin.text2 : Florin.text3)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.string(tx.day, locale: locale, t: t))
                    .font(.system(size: 14.5, weight: isNext ? .semibold : .medium))
                    .foregroundStyle(Florin.text)
                Text(
                    tx.isScheduled
                        ? t("v2.activity.scheduled", "Prévu")
                        : t("v2.instalments.settled", "Prélevée")
                )
                .font(.system(size: 12))
                .foregroundStyle(tx.isScheduled ? Florin.accent : Florin.text3)
            }
            Spacer(minLength: 8)
            AmountText(
                value: abs(tx.amount), locale: locale, currency: currency,
                tone: tx.isScheduled ? .neutral : .muted
            )
            if opens(tx) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .background(isNext ? Florin.accent.opacity(0.07) : .clear)
    }
}
