import SwiftUI

/*
 * What the bank actually said, run by run.
 *
 * Two tables recorded this from the first schema and nothing ever read them,
 * so every question of the form "the bank shows it and Florin does not" could
 * only be answered by argument. The interesting state is not success or
 * failure but `partial` — the bank answered, some accounts came back and some
 * did not — because from the outside that looks exactly like everything
 * working.
 */
struct SyncLogScreen: View {
    let t: Strings
    let locale: String

    @Environment(\.dismiss) private var dismiss
    @State private var runs: [SyncRun] = []
    @State private var opened: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

                if runs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 28))
                            .foregroundStyle(Florin.text3)
                        Text(t("v2.synclog.empty", "Aucune synchronisation enregistrée"))
                            .font(.system(size: 15))
                            .foregroundStyle(Florin.text2)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(runs) { run in
                                card(run)
                            }
                        }
                        .padding(.horizontal, Florin.gutter)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(t("v2.synclog.title", "Journal de synchro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    }
                    .accessibilityLabel(t("v2.common.close", "Fermer"))
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .task { runs = (try? LocalQueries.syncRuns(LocalStore.shared?.database)) ?? [] }
    }

    private func card(_ run: SyncRun) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if opened.contains(run.id) { opened.remove(run.id) } else { opened.insert(run.id) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(tone(run.status)).frame(width: 7, height: 7)
                        Text(when(run.startedAt))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Florin.text)
                        Text(label(run.trigger))
                            .font(.system(size: 11))
                            .foregroundStyle(Florin.text3)
                        Spacer(minLength: 4)
                        if !run.accounts.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Florin.text3)
                                .rotationEffect(.degrees(opened.contains(run.id) ? 180 : 0))
                        }
                    }
                    Text(summary(run))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text2)
                    if let error = run.errorSummary, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Florin.negative)
                            .lineLimit(3)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if opened.contains(run.id) {
                ForEach(run.accounts) { line in
                    Hairline()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The remote identifier, not our name for it: when the
                        // bank drops an account this is the only handle either
                        // side agrees on.
                        Text(String(line.uid.suffix(10)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Florin.text3)
                        Spacer(minLength: 6)
                        if let error = line.error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Florin.negative)
                                .lineLimit(2)
                        } else {
                            Text(t(
                                "v2.synclog.line", "{fetched} lues · {inserted} nouvelles",
                                ["fetched": line.fetched, "inserted": line.inserted]
                            ))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Florin.text2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
        }
        .florinSurface()
    }

    private func summary(_ run: SyncRun) -> String {
        var parts = [
            t("v2.synclog.accounts", "{ok}/{total} comptes",
              ["ok": run.accountsOk, "total": run.accountsTotal]),
            t("v2.synclog.inserted", "{count} opérations", ["count": run.inserted]),
        ]
        if let ms = run.durationMs, ms > 0 {
            parts.append(String(format: "%.1f s", Double(ms) / 1000))
        }
        return parts.joined(separator: " · ")
    }

    private func tone(_ status: String) -> Color {
        switch status {
        case "ok": Florin.positive
        case "partial": Florin.warn
        case "running": Florin.text3
        default: Florin.negative
        }
    }

    private func label(_ trigger: String) -> String {
        switch trigger {
        case "scheduler": t("v2.synclog.scheduler", "automatique")
        case "initial": t("v2.synclog.initial", "première")
        default: t("v2.synclog.manual", "manuelle")
        }
    }

    private func when(_ iso: String) -> String {
        guard let date = Timestamp.parse(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: locale)
        f.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return f.string(from: date)
    }
}

struct SyncRun: Identifiable {
    let id: String
    let startedAt: String
    let trigger: String
    let status: String
    let accountsTotal: Int
    let accountsOk: Int
    let inserted: Int
    let errorSummary: String?
    let durationMs: Int?
    var accounts: [SyncRunAccount]
}

struct SyncRunAccount: Identifiable {
    let id: String
    let uid: String
    let fetched: Int
    let inserted: Int
    let error: String?
}
