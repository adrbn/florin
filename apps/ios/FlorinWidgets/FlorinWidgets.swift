import SwiftUI
import WidgetKit

/*
 * What a finance widget is for.
 *
 * The first version led with net worth, which is the wrong number for a home
 * screen: it moves once a month, so on a screen someone sees eighty times a day
 * it says nothing new between glances. It is a figure you go and look at, not
 * one you keep an eye on.
 *
 * What earns the space is the question actually asked in a shop, several times
 * a week — can I spend this? That is what is left for the month, and it only
 * answers if it comes with how long it has to last. A number on its own is a
 * fact; the same number over eleven days is a decision.
 *
 * So the pace is the point: what the remainder allows per day, against what has
 * been spent per day so far. Above means the month ends short, and it says so
 * before the month does.
 */
struct FlorinWidgets: Widget {
    /// What WidgetKit already gave us. Read so that "follow the phone" can be
    /// passed straight back rather than replaced by a guess.
    @Environment(\.colorScheme) private var systemScheme

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlorinLeftToSpend", provider: Provider()) { entry in
            LeftToSpendView(entry: entry)
                .containerBackground(for: .widget) { WidgetGround() }
                /*
                 * The app's choice, not the phone's.
                 *
                 * Florin has its own appearance setting, and someone running
                 * iOS in light with the app set to dark had a pale tile sitting
                 * under a dark app — the one comparison a home screen makes for
                 * you. The snapshot carries the choice; nil means they asked to
                 * follow the phone, and then so does this.
                 */
                .environment(\.colorScheme, scheme(entry) ?? systemScheme)
        }
        .configurationDisplayName("Reste à vivre")
        .description("Ce qu'il vous reste pour le mois, et le rythme que ça autorise.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// `nil` when the app was left following the phone, in which case the widget
/// should too — WidgetKit already hands it the system appearance.
private func scheme(_ entry: Entry) -> ColorScheme? {
    switch entry.snapshot?.appearance {
    case "dark": .dark
    case "light": .light
    default: nil
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        /*
         * Refreshed on the hour, though rarely by it.
         *
         * The figures change when the app or its background sync writes a new
         * snapshot, and both reload the timeline themselves. The hour is a
         * floor, so a phone whose owner has not opened Florin in days still
         * comes back — which matters here, because the days remaining fall
         * whether or not anything was spent.
         */
        let entry = Entry(date: Date(), snapshot: WidgetSnapshot.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct LeftToSpendView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    /// The language the app was last in, carried by the snapshot. Before one
    /// exists there is nothing to translate but the "open Florin" prompt, and
    /// the handset's own language is the honest guess for that.
    private var t: WidgetStrings {
        WidgetStrings(locale: entry.snapshot?.locale ?? Locale.preferredLanguages.first ?? "en")
    }

    /// A snapshot older than a day and a half describes a month that has moved
    /// on without it. Said, rather than shown as though it were current.
    private var stale: Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.updatedAt) > 36 * 3600
    }

    var body: some View {
        /*
         * A tap turns the tile over rather than opening the app.
         *
         * Two views of one ledger do not deserve two tiles — nobody has the
         * room, and choosing between them at install time is a choice made
         * before knowing which one gets looked at. Interactive widgets landed
         * in iOS 17 and the floor here is 17.4, so the answer changes in place.
         */
        Button(intent: ToggleWidgetFaceIntent()) { face }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var face: some View {
        switch (snapshot, WidgetFace.current) {
        case let (.some(snapshot), .netWorth):
            netWorth(snapshot)
        case let (.some(snapshot), .leftToSpend) where snapshot.leftToSpend != nil:
            leftToSpend(snapshot, left: snapshot.leftToSpend ?? 0)
        case let (.some(snapshot), _):
            // No month to budget yet, but a net worth all the same — better the
            // figure it does have than the padlock.
            netWorth(snapshot)
        case (.none, _):
            locked
        }
    }

    // MARK: - What is left for the month

    private func leftToSpend(_ snapshot: WidgetSnapshot, left: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("v2.widget.leftToSpend", "Reste à vivre"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Florin.text2)

            Text(money(left, snapshot, decimals: false))
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold))
                    .foregroundStyle(left < 0 ? Florin.negative : Florin.text)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 1)

            if let days = snapshot.daysRemaining, days > 0 {
                    Text(t("v2.widget.daysLeft", "{count} jours restants", ["count": days]))
                        .font(.system(size: 12))
                        .foregroundStyle(Florin.text2)
            }

            Spacer(minLength: 6)

            pace(snapshot, left: left)

            if stale {
                    Text(t("v2.widget.asOf", "Chiffres du {date}",
                           ["date": day(snapshot.updatedAt)]))
                        .font(.system(size: 10))
                        .foregroundStyle(Florin.text3)
                        .padding(.top, 3)
            }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What it all adds up to

    private func netWorth(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("v2.widget.netWorth", "Patrimoine"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Florin.text2)

            Text(money(snapshot.netWorth, snapshot, decimals: false))
                .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold))
                .foregroundStyle(Florin.text)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 1)

            /*
             * The direction, or nothing.
             *
             * Net worth moves once a month, so the figure alone is the same
             * every time it is glanced at — which is exactly why it was taken
             * off the front. What makes it worth a look is which way it went,
             * and a month is the shortest window in which that means anything.
             */
            if let before = snapshot.netMonthAgo {
                let delta = snapshot.netWorth - before
                Text(t("v2.widget.overMonth", "{amount} sur un mois",
                       ["amount": money(delta, snapshot, decimals: false, signed: true)]))
                    .font(.system(size: 12))
                    .foregroundStyle(delta < 0 ? Florin.negative : Florin.positive)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6)

            if stale {
                Text(t("v2.widget.asOf", "Chiffres du {date}",
                       ["date": day(snapshot.updatedAt)]))
                    .font(.system(size: 10))
                    .foregroundStyle(Florin.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Nothing to show

    /*
     * Never a zero.
     *
     * A widget confidently printing 0 € is indistinguishable from a real
     * answer, and on an install with no shared container — every one signed
     * with a free Apple ID — it would print it for ever.
     */
    private var locked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "lock.circle")
                .font(.system(size: 20))
                .foregroundStyle(Florin.text3)
            Text(t("v2.widget.openApp", "Ouvrez Florin"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Florin.text)
            Text(t("v2.widget.openAppHint", "pour afficher vos chiffres ici"))
                .font(.system(size: 11))
                .foregroundStyle(Florin.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The comparison that makes the number actionable: what is allowed a day,
    /// against what has been spent a day.
    @ViewBuilder
    private func pace(_ snapshot: WidgetSnapshot, left: Double) -> some View {
        if let budget = snapshot.dailyBudget, budget > 0 {
            let spent = snapshot.dailySpent ?? 0
            let over = spent > budget
            VStack(alignment: .leading, spacing: 3) {
                if family != .systemSmall, spent > 0 {
                    // A bar of the allowed rate against the kept one — over one
                    // means the month runs out early.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Florin.text.opacity(0.14))
                            Capsule()
                                .fill(over ? Florin.negative : Florin.positive)
                                .frame(width: proxy.size.width * min(spent / budget, 1))
                        }
                    }
                    .frame(height: 5)
                    .padding(.bottom, 2)
                }

                // What the remainder allows, then what is actually being
                // spent. The colour carries the verdict; the words stay flat.
                Text(t("v2.widget.perDay", "{amount} par jour",
                       ["amount": money(budget, snapshot, decimals: false)]))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if spent > 0 {
                    Text(t("v2.widget.youSpend", "vous dépensez {amount}",
                           ["amount": money(spent, snapshot, decimals: false)]))
                        .font(.system(size: 11))
                        .foregroundStyle(over ? Florin.negative : Florin.text2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func money(
        _ value: Double, _ snapshot: WidgetSnapshot,
        decimals: Bool, signed: Bool = false
    ) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: snapshot.locale)
        f.currencyCode = snapshot.currency
        f.maximumFractionDigits = decimals ? 2 : 0
        // A rise needs its plus: without it "1 056 €" over a month could as
        // easily be what was lost.
        if signed, value > 0 { f.positivePrefix = "+" + (f.positivePrefix ?? "") }
        return f.string(from: NSNumber(value: value)) ?? "—"
    }

    private func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: entry.snapshot?.locale ?? "fr_FR")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }
}

@main
struct FlorinWidgetBundle: WidgetBundle {
    var body: some Widget { FlorinWidgets() }
}
