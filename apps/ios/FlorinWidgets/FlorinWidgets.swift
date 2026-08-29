import SwiftUI
import WidgetKit

/// The dashboard's first line, on the home screen.
struct FlorinWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlorinNetWorth", provider: Provider()) { entry in
            NetWorthView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.12, blue: 0.28),
                            Color(red: 0.05, green: 0.05, blue: 0.09),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Florin")
        .description("Votre patrimoine et ce qu'il vous reste pour le mois.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
         * One entry, refreshed in an hour.
         *
         * The figures only change when the app or its background sync writes a
         * new snapshot, and both reload the timeline themselves. The hour is a
         * floor so a widget on a phone whose owner has not opened Florin in
         * days still comes back to check rather than sitting on a stale entry
         * for ever.
         */
        let entry = Entry(date: Date(), snapshot: WidgetSnapshot.read())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct NetWorthView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 2) {
                Text("Patrimoine")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(money(snapshot.netWorth, snapshot))
                    .font(.system(size: family == .systemSmall ? 24 : 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let left = snapshot.leftToSpend {
                    Spacer(minLength: 6)
                    Text("Reste à vivre")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(money(left, snapshot))
                        .font(.system(size: family == .systemSmall ? 17 : 21, weight: .medium))
                        .foregroundStyle(left < 0 ? Color(red: 1, green: 0.42, blue: 0.42)
                                                  : Color(red: 0.35, green: 0.86, blue: 0.6))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            /*
             * Never a zero.
             *
             * A widget confidently printing 0,00 € is worse than a blank one:
             * it is indistinguishable from a real answer, and on an install
             * without a shared container it would print it for ever.
             */
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Ouvrez Florin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text("pour afficher vos chiffres ici")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func money(_ value: Double, _ snapshot: WidgetSnapshot) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: snapshot.locale)
        f.currencyCode = snapshot.currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "—"
    }
}

@main
struct FlorinWidgetBundle: WidgetBundle {
    var body: some Widget { FlorinWidgets() }
}
