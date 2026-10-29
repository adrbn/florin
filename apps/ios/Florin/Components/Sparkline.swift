import Charts
import SwiftUI

/*
 * Six mois de cours, dans la hauteur d'une ligne.
 *
 * Un titre affichait son prix et sa plus-value : deux nombres qui disent où on
 * en est, et rien de ce qui y a mené. Or c'est la forme qui décide — une même
 * plus-value de huit pour cent se garde si elle monte depuis trois mois et se
 * regarde autrement si elle redescend d'un sommet.
 *
 * Le trait pointillé est le prix de revient. Sans lui la courbe ne dirait que
 * le marché ; avec lui elle dit la position : au-dessus on gagne, en dessous on
 * perd, et l'écart se lit sans calcul. C'est aussi ce qui fixe la couleur —
 * verte ou rouge selon le côté où finit la courbe, pas selon sa pente, parce
 * qu'un titre qui remonte en restant sous son prix d'achat perd encore.
 *
 * Pas d'axes, pas de légende, pas de scrub : à cette taille, aucun n'est
 * lisible, et la version grand format vit dans la feuille du titre.
 */
struct Sparkline: View {
    let points: [LocalPricing.Point]
    /// Le prix de revient unitaire, quand on le connaît.
    var reference: Double?
    var height: CGFloat = 34

    /// Verte au-dessus du prix de revient, rouge en dessous. Sans référence,
    /// c'est la pente de la période qui tranche.
    private var tint: Color {
        guard let last = points.last?.close else { return Florin.text3 }
        let floor = reference ?? points.first?.close ?? last
        return last >= floor ? Florin.positive : Florin.negative
    }

    /*
     * Les bornes tiennent compte du trait pointillé.
     *
     * Un titre très au-dessus de son prix de revient a une courbe qui ne le
     * croise jamais : laisser Swift Charts cadrer sur les seuls cours sortirait
     * la référence du cadre, et un repère qu'on ne voit pas ne repère rien.
     *
     * La marge est proportionnelle à l'amplitude, pas fixe : un tracker à sept
     * cents euros et une action à trois euros n'ont pas le même centime.
     */
    private var bounds: ClosedRange<Double> {
        let values = points.map(\.close) + [reference].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        guard high > low else { return (low - 1)...(high + 1) }
        let margin = (high - low) * 0.12
        return (low - margin)...(high + margin)
    }

    var body: some View {
        Chart {
            if let reference {
                RuleMark(y: .value("Revient", reference))
                    .foregroundStyle(Florin.text3.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                AreaMark(
                    x: .value("Jour", index),
                    yStart: .value("Bas", bounds.lowerBound),
                    yEnd: .value("Cours", point.close)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Jour", index),
                    y: .value("Cours", point.close)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            // Le point du jour : sans lui, la courbe semble continuer hors cadre.
            if let last = points.last {
                PointMark(
                    x: .value("Jour", points.count - 1),
                    y: .value("Cours", last.close)
                )
                .foregroundStyle(tint)
                .symbolSize(22)
            }
        }
        .chartYScale(domain: bounds)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        // Une courbe de cours est une donnée de marché, pas un montant : elle
        // ne dit pas combien on a, donc le mode discret la laisse tranquille.
        .allowsHitTesting(false)
    }
}
