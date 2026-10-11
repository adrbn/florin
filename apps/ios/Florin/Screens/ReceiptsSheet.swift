import SwiftUI
import UIKit

/*
 * Ce qu'il y avait dans le panier.
 *
 * La banque dit « 39 € chez Le Comptoir » et s'arrête là. Le ticket de caisse
 * est la seule pièce qui dise de quoi ces 39 € étaient faits, et il finit à la
 * poubelle le soir même. Ici il est photographié, lu, et ses articles restent
 * avec l'opération — et surtout dans la recherche, qui les interroge comme
 * elle interroge un libellé ou un montant (voir `LocalWrites.searchClause`).
 *
 * Plusieurs tickets par opération : une même carte passe deux fois en caisse,
 * et un seul ticket n'explique alors qu'une partie du montant. D'où la ligne
 * « reste à détailler » plutôt qu'un contrôle qui refuserait : le total vient
 * de la banque, il n'est pas en doute ; l'écart dit seulement ce qui manque
 * encore, une photo ou une ligne mal lue.
 */
struct ReceiptsSheet: View {
    let tx: Transaction
    let locale: String
    let currency: String
    let t: Strings
    /// Appelé quand un ticket vient d'être ajouté ou retiré : la page dessous
    /// affiche le nombre d'articles et ne le sait pas toute seule.
    var onChanged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [LocalReceipts.Receipt] = []
    @State private var scanning = false
    @State private var reading = false
    @State private var failure: String?

    private var items: [LocalReceipts.Item] { receipts.flatMap(\.items) }
    private var remainder: Double {
        LocalReceipts.unexplained(total: tx.amount, items: items)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop(tint: TabRoute.activity.tint).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if reading { progress }
                        if receipts.isEmpty, !reading {
                            empty
                        } else {
                            ForEach(receipts) { receipt in
                                card(receipt)
                            }
                            if abs(remainder) > 0.005 { unexplained }
                        }
                        if let failure {
                            Text(failure)
                                .font(.system(size: 13))
                                .foregroundStyle(Florin.negative)
                        }
                        scan
                    }
                    .padding(.horizontal, Florin.gutter)
                    .padding(.vertical, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(t("v2.receipts.title", "Ticket de caisse"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { load() }
        .fullScreenCover(isPresented: $scanning) {
            ReceiptScanner { images in
                scanning = false
                read(images)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Les morceaux

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(PayeeText.title(tx.payee, category: tx.categoryName))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Florin.text)
                    .lineLimit(2)
                Text(DayLabel.string(tx.day, locale: locale, t: t))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
            }
            Spacer(minLength: 8)
            AmountText(
                value: tx.amount, locale: locale, currency: currency,
                signed: true, tone: .auto, size: 17, weight: .semibold
            )
        }
    }

    private var progress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(t("v2.receipts.reading", "Lecture du ticket…"))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("v2.receipts.empty", "Aucun ticket pour cette opération."))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Florin.text)
            Text(t(
                "v2.receipts.emptyHint",
                "Photographie le ticket : Florin en lit les articles et leurs prix, et les retrouve ensuite dans la recherche."
            ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)
        }
    }

    private func card(_ receipt: LocalReceipts.Receipt) -> some View {
        RowGroup {
            if receipt.items.isEmpty {
                line(t("v2.receipts.nothingRead", "Aucun article lu sur cette photo."), nil)
            } else {
                ForEach(Array(receipt.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline() }
                    line(item.label, item.amount)
                }
                Hairline()
                HStack {
                    Text(t("v2.receipts.receiptTotal", "Total du ticket"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.text2)
                    Spacer(minLength: 8)
                    AmountText(
                        value: receipt.total, locale: locale, currency: currency,
                        tone: .muted, size: 14
                    )
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 11)
            }
            Hairline()
            Button(role: .destructive) {
                guard let store = LocalStore.shared else { return }
                try? LocalReceipts.delete(store: store, receiptId: receipt.id)
                load()
                onChanged?()
            } label: {
                Text(t("v2.receipts.delete", "Supprimer ce ticket"))
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.vertical, 12)
            }
            .tint(Florin.negative)
        }
    }

    private func line(_ label: String, _ amount: Double?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Florin.text)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let amount {
                AmountText(value: amount, locale: locale, currency: currency)
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 11)
    }

    /// Ce que les articles n'expliquent pas. Pas une erreur : un ticket qui
    /// manque, ou une ligne que la photo n'a pas rendue.
    private var unexplained: some View {
        HStack(spacing: 8) {
            Text(t("v2.receipts.remainder", "Reste à détailler"))
                .font(.system(size: 14))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 8)
            AmountText(
                value: remainder, locale: locale, currency: currency,
                tone: .muted, size: 14
            )
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 11)
        .florinSurface()
    }

    private var scan: some View {
        Button {
            failure = nil
            scanning = true
        } label: {
            Label(
                receipts.isEmpty
                    ? t("v2.receipts.scan", "Scanner un ticket")
                    : t("v2.receipts.scanMore", "Scanner un autre ticket"),
                systemImage: "doc.viewfinder"
            )
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Florin.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        }
        .tint(Florin.accent)
        .buttonStyle(PressScale())
        .disabled(reading)
    }

    // MARK: - Lire et ranger

    private func load() {
        guard let store = LocalStore.shared else { return }
        receipts = (try? LocalReceipts.receipts(store: store, transactionId: tx.id)) ?? []
    }

    /*
     * La reconnaissance est lente — quelques secondes par ticket — et n'a
     * aucune raison de tenir l'écran. Les photos partent donc sur une tâche
     * de fond, et l'écriture revient sur le fil principal où la base est lue.
     */
    private func read(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        reading = true
        Task.detached(priority: .userInitiated) {
            var pages: [(Data?, String, [ReceiptParser.Item])] = []
            for image in images {
                let lines = (try? ReceiptOCR.lines(from: image)) ?? []
                pages.append((
                    ReceiptOCR.thumbnail(image),
                    lines.joined(separator: "\n"),
                    ReceiptParser.items(from: lines)
                ))
            }
            await MainActor.run {
                reading = false
                guard let store = LocalStore.shared else {
                    failure = (LocalStore.lastFailure ?? LocalWallet.Failure.noStore)
                        .localizedDescription
                    return
                }
                do {
                    for page in pages {
                        try LocalReceipts.save(
                            store: store, transactionId: tx.id,
                            image: page.0, text: page.1, items: page.2
                        )
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } catch {
                    failure = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                load()
                onChanged?()
            }
        }
    }
}
