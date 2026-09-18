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
            Line(symbol: "line.3.horizontal.decrease.circle",
                 key: "v2.news.1_3_6.filter",
                 fallback: "Le calendrier se filtre par catégorie, loyer compris."),
            Line(symbol: "hand.tap",
                 key: "v2.news.1_3_6.scrub",
                 fallback: "Maintenez un jour et glissez pour lire les montants."),
            Line(symbol: "chart.xyaxis.line",
                 key: "v2.news.1_3_6.running",
                 fallback: "Flux : le mois en cours ne tire plus la courbe vers le bas."),
            Line(symbol: "arrow.uturn.left",
                 key: "v2.news.1_3_6.refund",
                 fallback: "Un remboursement se classe avec l'achat, plus en revenu."),
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(release.lines) { line in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: line.symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Florin.accent)
                                .frame(width: 26, alignment: .center)
                            Text(t(line.key, line.fallback))
                                .font(.system(size: 15.5))
                                .foregroundStyle(Florin.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 26)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button { dismiss() } label: {
                Text(t("v2.common.continue", "Continuer"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Florin.gutter)
            .padding(.bottom, 18)
        }
        .background(Backdrop(tint: TabRoute.overview.tint, floor: true))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: t("v2.news.version", "Version {version}",
                            ["version": release.version]))
            Text(t("v2.news.title", "Ce qui est nouveau"))
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Florin.text)
        }
    }
}
