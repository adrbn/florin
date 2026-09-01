import SwiftUI

/// Pick the month whose amounts come across.
///
/// A list rather than a menu: the choice is between real months, and what makes
/// one the right answer is how much it holds — a month with three categories
/// budgeted is not the one to copy. So each line says.
struct PlanCopySheet: View {
    let sources: [LocalPlan.PlanSource]
    /// True when the month being copied into already has amounts. Nothing is
    /// overwritten either way, but someone who has started should be told.
    let hasAmounts: Bool
    let t: Strings
    let locale: String
    let currency: String
    let onPick: (LocalPlan.PlanSource) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.plan.tint, floor: true).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Florin.text2)
                            .frame(width: 30, height: 30)
                            .florinGlass(in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(t("v2.plan.copyPlan", "Reprendre le plan d'un autre mois"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Florin.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Color.clear.frame(width: 30, height: 30)
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 26)
                .padding(.bottom, 12)

                if hasAmounts {
                    Text(t(
                        "v2.plan.copyConfirmBody",
                        "Ce mois a déjà des montants. Seules les catégories vides seront remplies — rien de ce que vous avez saisi ne sera écrasé."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.warn)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 12)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                            if index > 0 { Hairline() }
                            Button {
                                working = true
                                Task {
                                    await onPick(source)
                                    working = false
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Self.monthName(source.year, source.month, locale))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Florin.text)
                                        Text(t(
                                            "v2.plan.sourceCategories", "{count} catégories",
                                            ["count": source.categories]
                                        ))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Florin.text3)
                                    }
                                    Spacer(minLength: 6)
                                    AmountText(
                                        value: source.total, locale: locale,
                                        currency: currency, decimals: false, size: 15
                                    )
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(working)
                        }
                    }
                    .florinSurface()
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
    }

    private static func monthName(_ year: Int, _ month: Int, _ locale: String) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return "\(month)/\(year)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        return f.string(from: date)
    }
}
