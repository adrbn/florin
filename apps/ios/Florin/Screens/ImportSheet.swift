import SwiftUI
import UniformTypeIdentifiers

/// Import a statement: pick the file, say which account it belongs to, see what
/// it holds, then commit. The middle step is the one that matters — a file is
/// the only thing entering this ledger that nothing has checked.
struct ImportSheet: View {
    let t: Strings
    let locale: String
    let currency: String
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var rows: [LocalImport.Row] = []
    @State private var order: LocalImport.DateOrder = .dayFirst
    @State private var rejected = 0
    @State private var fileName = ""
    @State private var accountId = ""
    @State private var accounts: [Account] = []
    @State private var failure: String?
    @State private var working = false
    @State private var done: (inserted: Int, skipped: Int)?

    var body: some View {
        ZStack {
            Backdrop(tint: Florin.sheetTint, floor: true).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if let done {
                    result(done)
                } else if rows.isEmpty {
                    invitation
                } else {
                    preview
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .task {
            guard let store = LocalStore.shared else { return }
            accounts = (try? LocalQueries.readAccounts(store.database)) ?? []
            if accountId.isEmpty { accountId = accounts.first?.id ?? "" }
        }
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .data]
        ) { result in
            guard case let .success(url) = result else { return }
            load(url)
        }
        .alert(
            t("v2.import.title", "Importer un relevé"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var header: some View {
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
            Text(t("v2.import.title", "Importer un relevé"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Florin.text)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, Florin.gutter)
        // Clear of the drag indicator, which sits in the first twenty points
        // and left the title looking pinned to the edge of the sheet.
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    private var invitation: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Florin.text3)
            Text(t(
                "v2.import.lead",
                "Le relevé CSV ou OFX téléchargé depuis le site de votre banque, pour un compte qu'elle ne synchronise pas."
            ))
            .font(.system(size: 14))
            .foregroundStyle(Florin.text2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 34)
            Button { picking = true } label: {
                Text(t("v2.import.choose", "Choisir un fichier"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal, 26)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var preview: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(fileName)
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text3)
                    .lineLimit(1)
                Text(t("v2.import.found", "{count} opérations", ["count": rows.count]))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Florin.text)
                if let first = rows.map(\.day).min(), let last = rows.map(\.day).max() {
                    Text("\(first) → \(last)")
                        .font(.system(size: 13))
                        .foregroundStyle(Florin.text2)
                }
                /*
                 * Said, not assumed.
                 *
                 * When every date in the file has both parts under thirteen
                 * nothing can tell 04/12 from 12/04. It is read the French way
                 * and the reading is stated, because the dates above are the
                 * one place someone can check it against what they remember.
                 */
                if order == .ambiguous {
                    Text(t(
                        "v2.import.ambiguousDates",
                        "Dates lues au format jour/mois. Vérifiez la période ci-dessus."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Florin.warn)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                }
                if order == .inconsistent {
                    Text(t(
                        "v2.import.inconsistentDates",
                        "Ce fichier mélange deux formats de date — souvent le signe qu'il a été rouvert dans Excel. Réexportez-le depuis votre banque."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Florin.negative)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 26)
                }
                if rejected > 0 {
                    Text(t(
                        "v2.import.rejected",
                        "{count} lignes ignorées : date illisible.", ["count": rejected]
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(Florin.warn)
                }
                AmountText(
                    value: rows.reduce(0) { $0 + $1.amount }, locale: locale,
                    currency: currency, signed: true, tone: .auto, size: 17, weight: .medium
                )
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: t("v2.import.intoAccount", "Sur quel compte"))
                Menu {
                    ForEach(accounts) { account in
                        Button(account.name) { accountId = account.id }
                    }
                } label: {
                    HStack {
                        Text(accounts.first { $0.id == accountId }?.name
                             ?? t("v2.import.pickAccount", "Choisir"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Florin.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Florin.text3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .florinGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, Florin.gutter)

            // The first few, verbatim: a file read with the wrong delimiter
            // produces rows that look plausible in a count and absurd in a list.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { index, row in
                        if index > 0 { Hairline() }
                        HStack(spacing: 10) {
                            Text(row.day)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Florin.text3)
                            Text(row.payee)
                                .font(.system(size: 13))
                                .foregroundStyle(Florin.text)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            AmountText(
                                value: row.amount, locale: locale, currency: currency,
                                signed: true, tone: .auto, size: 13, weight: .medium
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
                .florinSurface()
                .padding(.horizontal, Florin.gutter)
            }
            .scrollIndicators(.hidden)

            Button { commit() } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.black) }
                    Text(t("v2.import.commit", "Importer"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(working || accountId.isEmpty || order == .inconsistent)
            .opacity(accountId.isEmpty || order == .inconsistent ? 0.4 : 1)
            .padding(.horizontal, Florin.gutter)
            .padding(.bottom, 12)
        }
    }

    private func result(_ done: (inserted: Int, skipped: Int)) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Florin.positive)
            Text(t("v2.import.done", "{count} opérations ajoutées", ["count": done.inserted]))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Florin.text)
            if done.skipped > 0 {
                Text(t(
                    "v2.import.skipped",
                    "{count} déjà présentes, ignorées.", ["count": done.skipped]
                ))
                .font(.system(size: 13.5))
                .foregroundStyle(Florin.text2)
            }
            Text(t("v2.import.review", "Elles vous attendent dans « à vérifier »."))
                .font(.system(size: 13.5))
                .foregroundStyle(Florin.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try LocalImport.parse(data: data, fileName: url.lastPathComponent)
            rows = parsed.rows
            order = parsed.order
            rejected = parsed.rejected
            fileName = url.lastPathComponent
        } catch {
            failure = error.localizedDescription
        }
    }

    private func commit() {
        guard let store = LocalStore.shared else { return }
        working = true
        Task {
            do {
                let counts = try LocalLedger.importRows(
                    store: store, accountId: accountId, rows: rows
                )
                await onDone()
                working = false
                done = counts
            } catch {
                working = false
                failure = error.localizedDescription
            }
        }
    }
}
