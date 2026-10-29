import Foundation

/*
 * Où va finir le mois, calculé une seule fois.
 *
 * Le mélange vivait dans `OverviewScreen.monthEnd` : soixante lignes de
 * pondération au milieu d'une vue. L'accueil éditorial demande la même
 * marge, et la recopier aurait fait deux vérités — celle qu'on corrige et
 * celle qu'on oublie. C'est la même que `computeMonthForecast` côté web.
 *
 * Un mois est deux choses : des charges qui tombent le jour que la banque
 * choisit mais qui tombent, et une habitude quotidienne qui peut vraiment
 * être plus légère que d'ordinaire. La part fixe est portée entière ; la
 * part variable est un rythme par jour, mêlé à l'historique du compte selon
 * la part du mois déjà observée.
 */
struct MonthForecast {
    /// Ce qui aura été dépensé, net des remboursements.
    let projected: Double
    /// Ce qu'il restera, quand un revenu du mois est connu.
    let margin: Double?
    /// Les charges fixes retenues : celles déjà passées, ou celles attendues.
    let fixedComponent: Double
    let variableSpent: Double
    let daysInMonth: Double
    let elapsed: Double

    init(_ lts: LeftToSpend) {
        // Le poids de l'habitude décroît à mesure que le mois se remplit :
        // trois jours ne disent rien, le 28 dit presque tout. 60 est le
        // minimum que la mesure donne ; voir computeMonthForecast.
        let priorDays = 60.0
        daysInMonth = Double(lts.daysElapsed + lts.daysRemaining)
        elapsed = Double(lts.daysElapsed)
        let priorWeight = daysInMonth > 0 ? priorDays * (1 - elapsed / daysInMonth) : 0
        let expectedFixed = lts.expectedMonthlyFixed ?? 0
        variableSpent = max(0, lts.monthSpent - lts.monthSpentFixed)
        let observedDaily = elapsed > 0 ? variableSpent / elapsed : 0
        let priorDaily = daysInMonth > 0
            ? max(0, lts.expectedMonthlySpend - expectedFixed) / daysInMonth
            : 0
        let weight = elapsed + priorWeight
        let blendedDaily = weight > 0
            ? (elapsed * observedDaily + priorWeight * priorDaily) / weight
            : observedDaily
        fixedComponent = max(lts.monthSpentFixed, expectedFixed)
        let projectedGross = max(lts.monthSpent, blendedDaily * daysInMonth + fixedComponent)
        /*
         * Brut projeté, marge nette — voir computeMonthForecast.
         *
         * Les remboursements arrivent par paquets et en retard : un modèle
         * nourri de dépenses nettes cesse de croire au mois qu'il décrit. Le
         * brut est la série prévisible ; ce qui est déjà revenu est
         * simplement connu, donc retiré. Ceux à venir sont mêlés de la même
         * façon que la dépense — l'habitude mène tôt, ce qui a atterri
         * décide tard — et jamais sous ce qui est réellement revenu.
         */
        let refunds = lts.monthRefunds ?? 0
        let observedRefundDaily = elapsed > 0 ? refunds / elapsed : 0
        let priorRefundDaily = daysInMonth > 0
            ? max(0, lts.expectedMonthlyRefunds ?? 0) / daysInMonth
            : 0
        let blendedRefundDaily = weight > 0
            ? (elapsed * observedRefundDaily + priorWeight * priorRefundDaily) / weight
            : observedRefundDaily
        let projectedRefunds = max(refunds, blendedRefundDaily * daysInMonth)
        projected = max(lts.monthSpent - refunds, projectedGross - projectedRefunds)
        margin = lts.monthIncome > 0 ? lts.monthIncome - projected : nil
    }
}
