import SwiftUI

/// What the dashboard shows before there is anything to show.
///
/// A fresh install used to land on a screen of zeros: 0,00 € of net worth,
/// 0 € left to spend, −0 € spent, an empty chart. Every figure was correct and
/// the screen was useless — it answered questions nobody had yet and offered
/// nothing to do about it. Worse, it looked broken rather than new.
///
/// So the zeros are replaced, not decorated. One sentence about what happens
/// next, and the two ways to make it happen — the bank, or by hand.
struct EmptyStart: View {
    let t: Strings
    let onConnectBank: () -> Void
    let onAddManually: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image("CoinFace")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)

                Text(t("v2.empty.title", "Rien à afficher — pour l'instant"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Florin.text)
                    .multilineTextAlignment(.center)

                Text(t(
                    "v2.empty.body",
                    "Florin lit vos comptes et vous dit où part votre argent, ce qu'il vous reste, et comment votre patrimoine évolue. Il lui faut d'abord de quoi lire."
                ))
                .font(.system(size: 14.5))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 26)

            VStack(spacing: 10) {
                choice(
                    emoji: "🏛️",
                    title: t("v2.empty.bankTitle", "Connecter ma banque"),
                    detail: t(
                        "v2.empty.bankBody",
                        "Comptes, soldes et opérations arrivent tout seuls. Environ deux minutes, une seule fois."
                    ),
                    prominent: true,
                    action: onConnectBank
                )
                choice(
                    emoji: "✍️",
                    title: t("v2.empty.manualTitle", "Ajouter un compte à la main"),
                    detail: t(
                        "v2.empty.manualBody",
                        "Vous entrez le solde, puis vos opérations au fur et à mesure."
                    ),
                    prominent: false,
                    action: onAddManually
                )
            }
            .padding(.horizontal, Florin.gutter)

            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                Text(t("v2.empty.privacy", "Tout reste sur ce téléphone."))
                    .font(.system(size: 12))
            }
            .foregroundStyle(Florin.text3)
            .padding(.top, 20)

            // What the app will look like once it has something — the point of
            // doing any of the above, shown rather than promised.
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: t("v2.empty.preview", "Ce que vous verrez"))
                    .padding(.horizontal, Florin.gutter)

                VStack(spacing: 0) {
                    previewRow("chart.line.uptrend.xyaxis",
                               t("v2.empty.previewWealth", "Votre patrimoine, mois après mois"))
                    Hairline()
                    previewRow("chart.pie.fill",
                               t("v2.empty.previewSpend", "Où part l'argent, par catégorie"))
                    Hairline()
                    previewRow("calendar",
                               t("v2.empty.previewLeft", "Ce qu'il vous reste jusqu'à la fin du mois"))
                }
                .florinSurface()
                .padding(.horizontal, Florin.gutter)
            }
            .padding(.top, 34)
        }
        .padding(.bottom, 40)
    }

    private func choice(
        emoji: String,
        title: String,
        detail: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(prominent ? .black : Florin.text)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(prominent ? .black.opacity(0.7) : Florin.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(prominent ? .black.opacity(0.5) : Florin.text3)
            }
            .padding(16)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Florin.accent)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Florin.surface)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func previewRow(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Florin.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 13)
    }
}
