import SwiftUI

/*
 * Le bas de l'accueil éditorial : ce que dit le mois.
 *
 * Obsidienne portait déjà ces quatre choses — marge prévue, reste à vivre,
 * répartition, taux d'épargne — en cartes empilées. Ici elles tiennent en
 * barres et en filets : une barre dit une proportion mieux qu'un anneau, et
 * un filet entre deux lignes coûte un point là où une carte en coûte vingt.
 *
 * Rien ne calcule : tout vient d'`Overview` et de `MonthForecast`, la même
 * arithmétique que l'autre écran.
 */

// MARK: - Quels comptes ont leur carte

/// Les comptes écartés de la pile de l'accueil.
///
/// Un trousseau de douze comptes ne fait pas douze cartes à regarder le
/// matin : la pile se tasse jusqu'à son pas plancher et finit par ne plus
/// rien montrer d'autre que des bandeaux. Le choix se fait compte par
/// compte, là où on le renomme — `AccountEditSheet` — et vit dans les
/// réglages de l'appareil, pas dans le grand livre : c'est une préférence
/// d'affichage, elle n'a pas à voyager avec les données.
enum HomeCards {
    static let key = "florin.homeCards.hidden"

    /// Les identifiants écartés. Séparés par des sauts de ligne, qu'un
    /// identifiant ne peut pas contenir.
    static func hidden(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    /// Le rang de `Florin.series` écrit dans `display_color`, s'il y en a un.
    /// Voir `Account.displayColor` pour pourquoi c'est un rang.
    static func colorSlot(_ raw: String?) -> Int? {
        guard let raw, raw.hasPrefix("series-") else { return nil }
        return Int(raw.dropFirst(7))
    }

    static func slotName(_ slot: Int) -> String { "series-\(slot)" }

    /*
     * Une couleur par compte, et jamais deux fois la même.
     *
     * `seriesColor` hache l'identifiant sur huit teintes : à six comptes, deux
     * tombent sur la même plus d'une fois sur deux — PEA et LEP étaient tous
     * les deux jaunes, l'un sur l'autre, et la pile n'avait plus que cinq
     * cartes à l'œil. Le hachage reste le premier choix, parce que c'est lui
     * qui rend la couleur stable et la même que sur le web ; un compte qui
     * trouve sa place prise passe au rang suivant.
     *
     * Décidée sur l'ordre de la BASE, pas sur l'ordre affiché : mettre une
     * carte en avant réordonne la pile, et une couleur qui suivrait cet ordre
     * changerait à chaque appui.
     */
    static func palette(_ all: [Account]) -> [String: Color] {
        let count = Florin.series.count
        var taken = Set<Int>()
        var out: [String: Color] = [:]
        /*
         * Les teintes choisies à la main passent devant.
         *
         * Elles réservent leur rang, et ce sont les automatiques qui
         * s'écartent ensuite. Dans l'autre sens, un compte au hasard pouvait
         * occuper la teinte demandée et pousser le choix explicite ailleurs —
         * c'est-à-dire ne pas le tenir.
         */
        for account in all {
            if let slot = HomeCards.colorSlot(account.displayColor), slot >= 0, slot < count {
                taken.insert(slot)
                out[account.id] = Florin.series[slot]
            }
        }
        for account in all where out[account.id] == nil {
            var rank = Florin.seriesIndex(for: account.id)
            var tries = 0
            while taken.contains(rank), tries < count {
                rank = (rank + 1) % count
                tries += 1
            }
            taken.insert(rank)
            out[account.id] = Florin.series[rank]
        }
        return out
    }

    static func write(_ id: String, shown: Bool, in raw: String) -> String {
        var set = hidden(raw)
        if shown { set.remove(id) } else { set.insert(id) }
        return set.sorted().joined(separator: "\n")
    }
}

// MARK: - Les quatre gestes

/*
 * Toujours à la même place, toujours les mêmes quatre.
 *
 * Ce qu'on fait à l'accueil se compte sur une main : noter ce qu'on vient de
 * payer, noter ce qui vient de rentrer, redemander à la banque, aller voir un
 * compte. Trois d'entre eux existaient, répartis entre un onglet, une icône de
 * bandeau et une pastille de titre. Les quatre se lisent ici d'un coup d'œil.
 */
struct EdActions: View {
    let t: Strings
    let syncing: Bool
    let canSync: Bool
    let onExpense: () -> Void
    let onIncome: () -> Void
    let onSync: () -> Void
    let onAccounts: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            gesture("minus", t("v2.ed.expense", "Dépense"), action: onExpense)
            gesture("plus", t("v2.ed.income", "Reçu"), action: onIncome)
            gesture(
                "arrow.trianglehead.2.clockwise",
                t("v2.common.refresh", "Synchro"),
                spinning: syncing, enabled: canSync, action: onSync
            )
            gesture("rectangle.stack", t("v2.nav.accounts", "Comptes"), action: onAccounts)
        }
    }

    private func gesture(
        _ symbol: String, _ label: String,
        spinning: Bool = false, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(
                        spinning
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: spinning
                    )
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Florin.text)
            .frame(maxWidth: .infinity)
            // 44 pt de haut : c'est une cible, pas une légende.
            .frame(height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: Ed.smallCard, style: .continuous)
                    .strokeBorder(Florin.text.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.edPress)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

// MARK: - Le mois en trois parts

/*
 * Une barre, trois parts, trois chiffres — et un repère.
 *
 * Un anneau demande de comparer des angles ; une barre se lit comme une
 * phrase, de gauche à droite. Les trois parts sont ce que le mois a fait de
 * son revenu : la dépense du quotidien, les charges qui tombent de toute
 * façon, ce qui reste.
 *
 * Le repère est le trait d'accent : là où la dépense devrait en être au jour
 * d'aujourd'hui, si le mois se dépensait régulièrement. L'écart se dit en
 * JOURS plutôt qu'en pourcents — « trois jours d'avance » se comprend sans
 * calcul, « 41 % contre 52 % » demande de faire la soustraction.
 */
struct EdMonthSplit: View {
    let data: Overview

    var body: some View {
        let lts = data.leftToSpend
        let variable = max(0, lts.monthSpent - lts.monthSpentFixed)
        let fixed = max(0, lts.monthSpentFixed)
        let rest = max(0, lts.leftToSpend)
        let total = max(lts.monthIncome > 0 ? lts.monthIncome : variable + fixed + rest, 1)
        let days = Double(lts.daysElapsed + lts.daysRemaining)
        let budget = max(lts.expectedMonthlySpend, 1)
        // Où la dépense devrait en être, posée sur le même axe que les parts.
        let pace = days > 0 ? (Double(lts.daysElapsed) / days) * budget / total : 0

        return VStack(alignment: .leading, spacing: 14) {
            EdSection(
                text: t("v2.ed.thisMonth", "Ce mois-ci"),
                trailing: t("v2.overview.daysLeft", "{count} j restants",
                            ["count": lts.daysRemaining])
            )
            EdParts(
                parts: [
                    .init(value: variable, tone: Florin.text),
                    .init(value: fixed, tone: Florin.text.opacity(0.38)),
                ],
                total: total,
                mark: pace > 0 && pace < 1 ? pace : nil
            )
            /*
             * Les deux premiers chiffres sont ce qui est SORTI — du rouge le
             * dirait trois fois (le signe, la part de barre, la couleur) et
             * ferait d'une dépense ordinaire une alerte. Seul le reste à
             * vivre change de camp selon qu'il existe encore ou non.
             */
            EdFigures(figures: [
                .init(
                    label: t("v2.ed.daily", "Quotidien"),
                    text: money(variable), tone: Florin.text
                ),
                .init(
                    label: t("v2.ed.fixed", "Charges"),
                    text: money(fixed), tone: Florin.text2
                ),
                .init(
                    label: t("v2.overview.leftToSpend", "Reste"),
                    text: money(rest),
                    tone: lts.leftToSpend >= 0 ? Florin.positive : Florin.negative
                ),
            ])
        }
    }

    /*
     * Pas de phrase sous les chiffres.
     *
     * Il y en avait une : « Au 29, tu devrais être à 94 % du budget. Tu es à
     * 91 % — 1 j d'avance. » Trois nombres pour dire ce que le repère rouge
     * sur la barre dit d'un coup d'œil, sur deux lignes, dans une grammaire
     * que personne n'emploie. Le repère reste, la phrase part.
     */

    private func t(
        _ key: String, _ fallback: String, _ args: [String: CustomStringConvertible] = [:]
    ) -> String {
        args.isEmpty ? data.t(key, fallback) : data.t(key, fallback, args)
    }

    private func money(_ value: Double) -> String {
        Money.string(value, locale: data.localeTag, currency: data.currency, decimals: false)
    }
}

// MARK: - La fin du mois

/// Ce qu'il restera, et ce qu'il reste par jour.
///
/// Deux lignes sous un filet, pas deux cartes : la marge prévue et le reste à
/// vivre répondent à la même question à deux échéances, et les empiler les
/// fait lire ensemble.
struct EdMonthEnd: View {
    let data: Overview

    var body: some View {
        let lts = data.leftToSpend
        let forecast = MonthForecast(lts)
        return VStack(alignment: .leading, spacing: 2) {
            EdSection(text: data.t("v2.overview.forecast", "Fin de mois"))
            /*
             * Le même écart sous ce titre que sous les autres.
             *
             * Une rangée alignée sur la première ligne de base porte la hauteur
             * de son plus GRAND texte : le chiffre de 28 pt met seize points
             * de blanc au-dessus de l'étiquette de 15, et le titre avait l'air
             * de s'être décollé de sa section. « Ce mois-ci » et « Répartition »
             * sont suivis d'une barre, qui n'a pas d'ascendante — d'où douze
             * points d'écart entre deux sections censées battre la même mesure.
             */
            VStack(spacing: 0) {
                row(
                    data.t("v2.overview.forecastMargin", "Marge prévue"),
                    forecast.margin.map {
                        Money.string(
                            $0, locale: data.localeTag, currency: data.currency,
                            decimals: false, signed: true
                        )
                    },
                    tone: (forecast.margin ?? 0) >= 0 ? Florin.positive : Florin.negative,
                    note: data.t(
                        "v2.ed.projectedSpend", "{amount} dépensés sur le mois",
                        ["amount": Money.string(
                            forecast.projected, locale: data.localeTag,
                            currency: data.currency, decimals: false
                        )]
                    )
                )
                EdRule()
                row(
                    data.t("v2.overview.leftToSpend", "Reste à vivre"),
                    Money.string(
                        lts.leftToSpend, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    ),
                    tone: lts.leftToSpend >= 0 ? Florin.text : Florin.negative,
                    note: lts.dailyBudgetRemaining.map {
                        Money.string(
                            $0, locale: data.localeTag, currency: data.currency, decimals: false
                        )
                            + data.t("v2.common.perDay", "/jour") + " · "
                            + data.t("v2.overview.daysLeft", "{count} j restants",
                                     ["count": lts.daysRemaining])
                    } ?? data.t(
                        "v2.overview.leftToSpendNone", "Aucun salaire détecté sur 90 jours"
                    )
                )
            }
            // Les seize points que l'ascendante du chiffre ajoute au-dessus de
            // la première étiquette, rendus au titre.
            .padding(.top, -12)
            if data.incomeIsEstimated {
                // Sinon la ligne réclame doucement un argent qui n'est pas
                // arrivé : avant la paie, « le revenu du mois » est celui du
                // mois d'avant.
                Text(data.t(
                    "v2.overview.incomeEstimated",
                    "Salaire du mois pas encore reçu — basé sur le précédent"
                ))
                .font(.system(size: 13))
                .foregroundStyle(Florin.negative.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(
        _ label: String, _ amount: String?, tone: Color, note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text)
                Spacer(minLength: 10)
                if let amount {
                    /*
                     * Deux montants l'un sous l'autre, un seul bord droit.
                     *
                     * `minimumScaleFactor` rapetisse le plus long sans
                     * rétrécir son cadre, et un texte rapetissé se range du
                     * côté de `multilineTextAlignment` — à gauche par défaut.
                     * Le chiffre décollait donc du bord, et seulement celui-là.
                     */
                    EdAmount(text: amount, size: 28, tone: tone)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("—").foregroundStyle(Florin.text3)
                }
            }
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(Florin.text3)
                .lineLimit(2)
                .hiddenWhenPrivate()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - La répartition

/// Où l'argent est posé : liquide, investi, prêté à la banque.
struct EdAllocation: View {
    let data: Overview

    var body: some View {
        let cash = max(0, data.allocation.cash)
        let invested = max(0, data.allocation.invested)
        let loans = max(0, abs(data.allocation.loans))
        let total = max(cash + invested + loans, 1)
        return VStack(alignment: .leading, spacing: 14) {
            EdSection(text: data.t("v2.overview.allocation", "Répartition"))
            EdParts(
                parts: [
                    .init(value: cash, tone: Florin.series[0]),
                    .init(value: invested, tone: Florin.series[2]),
                    .init(value: loans, tone: Florin.text.opacity(0.22)),
                ],
                total: total
            )
            EdFigures(figures: [
                .init(
                    label: data.t("v2.overview.cash", "Liquidités"),
                    text: money(cash), tone: Florin.series[0]
                ),
                .init(
                    label: data.t("v2.overview.invested", "Investi"),
                    text: money(invested), tone: Florin.series[2]
                ),
                .init(
                    label: data.t("v2.overview.debt", "Dettes"),
                    text: money(loans), tone: Florin.text2
                ),
            ])
        }
    }

    private func money(_ value: Double) -> String {
        Money.string(value, locale: data.localeTag, currency: data.currency, decimals: false)
    }
}

// MARK: - Le taux d'épargne

/// Trois fenêtres, trois chiffres, et ce que la plus courte vaut.
///
/// Elles ne portent que des mois COMPLETS — le mois en cours a ses dépenses
/// mais pas encore son salaire, et l'y mettre faisait plonger la fenêtre de
/// trois mois pendant que celle de douze n'y voyait rien.
struct EdSavings: View {
    let data: Overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EdSection(text: data.t("v2.overview.savingsRate", "Taux d'épargne"))
            HStack(alignment: .top, spacing: 0) {
                window("3 " + months, data.savings.threeMonth)
                window("6 " + months, data.savings.sixMonth)
                window("12 " + months, data.savings.twelveMonth)
            }
            Text(data.t(
                "v2.overview.savingsRateHint", "Épargné ÷ revenus, sur mois complets"
            ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text3)
        }
    }

    private var months: String { data.t("v2.common.months", "mois") }

    private func window(_ label: String, _ rate: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
            // Les taux arrivent déjà en pourcents — `Money.percent` divise
            // par cent, donc les multiplier ici les centuplerait.
            PrivateText(Money.percent(rate, locale: data.localeTag, digits: 0))
                .font(.system(size: 30, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(
                    rate == nil
                        ? Florin.text3
                        : ((rate ?? 0) >= 0 ? Florin.positive : Florin.negative)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Les deux primitives

/// Une barre en plusieurs parts, et parfois un repère.
///
/// Les écarts entre les parts sont pris sur la largeur AVANT de répartir, sans
/// quoi la somme des parts dépasse la barre et la dernière se fait rogner.
struct EdParts: View {
    struct Part {
        let value: Double
        let tone: Color
    }

    let parts: [Part]
    let total: Double
    /// Entre 0 et 1, sur le même axe que les parts.
    var mark: Double?
    var height: CGFloat = 12

    /*
     * UNE barre, découpée — et non des barres posées bout à bout.
     *
     * Chaque part était une capsule avec trois points d'écart : la part noire
     * finissait donc par un demi-cercle et la grise recommençait par l'autre
     * moitié, ce qui se lit comme deux objets qui se touchent plutôt que
     * comme une jauge et son reste. Ici le creux est une seule capsule, les
     * parts sont des rectangles sans écart, et c'est le découpage de
     * l'ensemble qui arrondit les deux bouts — les seuls qui soient des bords.
     */
    var body: some View {
        GeometryReader { geo in
            let shown = parts.filter { $0.value > 0 }
            ZStack(alignment: .leading) {
                Capsule().fill(Florin.text.opacity(0.10))
                HStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                        Rectangle()
                            .fill(part.tone)
                            .frame(width: geo.size.width * CGFloat(min(part.value / total, 1)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipShape(Capsule())
                if let mark {
                    Capsule()
                        .fill(Florin.accent)
                        .frame(width: 2, height: height + 8)
                        .offset(x: geo.size.width * CGFloat(mark) - 1)
                }
            }
            .frame(height: height, alignment: .center)
        }
        .frame(height: height + 8)
    }
}

/// Trois chiffres sous une barre, dans l'ordre de la barre.
struct EdFigures: View {
    struct Figure {
        let label: String
        let text: String
        let tone: Color
    }

    let figures: [Figure]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                VStack(alignment: .leading, spacing: 4) {
                    Text(figure.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Florin.text2)
                        .lineLimit(1)
                    PrivateText(figure.text)
                        .font(.system(size: 19, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(figure.tone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Le rideau, à côté du chiffre

/*
 * L'œil qui masque les montants.
 *
 * Pas un `Button` : il vit à l'intérieur du label d'un autre bouton — celui
 * qui bascule net et brut — et un bouton imbriqué dans le label d'un bouton
 * ne reçoit jamais le toucher. Une cible et un `onTapGesture`, comme la ligne
 * en dessous qui bascule déjà de la même façon.
 */
struct EdEye: View {
    @ObservedObject private var privacy = Privacy.shared

    var body: some View {
        Image(systemName: privacy.hidden ? "eye.slash" : "eye")
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)
            // La cible garde ses 44 pt — c'est le minimum d'un doigt — mais le
            // glyphe se range à son bord gauche : sinon l'œil flotte à vingt
            // points de la pastille qu'il concerne.
            .frame(width: 44, height: 24, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { privacy.toggle() }
            .accessibilityLabel(privacy.hidden ? "Afficher les montants" : "Masquer les montants")
    }
}
