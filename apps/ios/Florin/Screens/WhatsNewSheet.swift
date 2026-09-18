import SwiftUI

/// What changed, said once per version.
///
/// A TestFlight build arrives with no covering letter: the calendar gains a
/// filter, the flows chart stops lying about the running month, and the only
/// way to find out is to go looking. Four lines on the first launch after an
/// update is the whole feature — not a changelog, not a feed, and never
/// twice.
///
/// Notes are written by hand, one release at a time, and they live in the
/// string catalogue like every other sentence in the app: a release nobody
/// translated fails the parity test rather than showing French to everyone
/// else. A version with no entry here simply shows nothing.
enum ReleaseNotes {
    struct Line: Identifiable {
        let symbol: String
        let key: String
        let fallback: String
        var id: String { key }
    }

    struct Release: Identifiable {
        let version: String
        let lines: [Line]
        var id: String { version }
    }

    static let all: [Release] = [
        Release(version: "1.3.6", lines: [
            Line(symbol: "calendar",
                 key: "v2.news.1_3_6.calendar",
                 fallback: "Le calendrier va mois par mois, aussi loin que votre historique, et se filtre par catégorie."),
            Line(symbol: "hand.tap",
                 key: "v2.news.1_3_6.scrub",
                 fallback: "Maintenez un jour et glissez pour lire les montants."),
            Line(symbol: "chart.xyaxis.line",
                 key: "v2.news.1_3_6.running",
                 fallback: "Flux : le mois en cours ne tire plus la courbe vers le bas."),
            Line(symbol: "arrow.triangle.2.circlepath",
                 key: "v2.news.1_3_6.subs",
                 fallback: "Les abonnements sont retrouvés même quand la banque change le libellé à chaque prélèvement."),
            Line(symbol: "arrow.uturn.left",
                 key: "v2.news.1_3_6.refund",
                 fallback: "Un remboursement se classe avec l'achat, plus en revenu."),
            Line(symbol: "slider.horizontal.3",
                 key: "v2.news.1_3_6.edit",
                 fallback: "Modifier une opération propose tout ce que l'ajout propose — le réglage « en prévision » compris."),
            Line(symbol: "wifi.slash",
                 key: "v2.news.1_3_6.offline",
                 fallback: "Sans connexion, Florin affiche ses derniers chiffres au lieu de tourner dans le vide."),
            Line(symbol: "globe",
                 key: "v2.news.1_3_6.turkish",
                 fallback: "L'app parle turc."),
        ]),
    ]

    /// The version this build calls itself, as Settings shows it.
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// What to show now, if anything.
    ///
    /// `seen` is empty on a fresh install *and* on the first launch after this
    /// feature shipped, which are not the same thing: one has never used
    /// Florin and has nothing to be told about, the other has a ledger and has
    /// just been handed a new build. `hasLedger` is what tells them apart.
    static func pending(seen: String, hasLedger: Bool) -> Release? {
        guard seen != current else { return nil }
        guard !seen.isEmpty || hasLedger else { return nil }
        return all.first { $0.version == current }
    }
}

struct WhatsNewSheet: View {
    let release: ReleaseNotes.Release
    let t: Strings
    @Environment(\.dismiss) private var dismiss
    /// The notes' own height, so the sheet is exactly as tall as what it has
    /// to say — see `detent`.
    @State private var measured: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(release.lines) { line in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: line.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Florin.accent)
                                .frame(width: 24, alignment: .center)
                                // Optically on the first line of the sentence
                                // beside it, not on its cap height.
                                .padding(.top, 1)
                            Text(t(line.key, line.fallback))
                                .font(.system(size: 15))
                                .foregroundStyle(Florin.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .background(measurement)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button { dismiss() } label: {
                Text(t("v2.common.continue", "Continuer"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Florin.gutter)
            .padding(.bottom, 14)
        }
        .background(Backdrop(tint: TabRoute.overview.tint))
        .presentationDetents([detent])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    /*
     * As tall as the notes, not half the screen.
     *
     * `.medium` is a fraction of the display and knows nothing about what is
     * on it: six lines overflowed it, the last one ran under the button, and
     * the two after that were only findable by scrolling a sheet that gave no
     * sign it could scroll. Measuring what is actually there and asking for
     * that height makes the sheet fit its contents at any text size — and
     * still scroll, clamped, when someone reads at 200%.
     */
    private var detent: PresentationDetent {
        let chrome: CGFloat = 52 + 14 + 16
        let ceiling = UIScreen.main.bounds.height * 0.86
        return .height(min(max(measured + chrome, 260), ceiling))
    }

    private var measurement: some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                measured = height
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: t("v2.news.version", "Version {version}",
                            ["version": release.version]))
            Text(t("v2.news.title", "Ce qui est nouveau"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Florin.text)
        }
    }
}
