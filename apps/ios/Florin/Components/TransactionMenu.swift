import SwiftUI
import UIKit

/*
 * A long press on a transaction, with what can be done to it.
 *
 * Every action lived one level down, in the detail sheet: open the row, then
 * choose. For the things done most — filing it, marking it checked, calling
 * it an internal transfer — that is a sheet opened only to be closed again.
 * The menu reaches each of them in one gesture, on the Aperçu and in Activité
 * alike, and each opens exactly the sheet it needs.
 *
 * The row says what it wants; `TransactionActionsHost`, attached once to the
 * screen, owns the sheets. Rows in a list cannot each own a sheet.
 */

enum TxAction: String {
    case approve, categorize, rename, refund, receipt, transfer, edit, delete
}

struct TxActionRequest: Identifiable, Equatable {
    let action: TxAction
    let tx: Transaction
    var id: String { "\(action.rawValue)-\(tx.id)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension View {
    func transactionMenu(
        _ tx: Transaction,
        t: Strings,
        locale: String,
        currency: String,
        canTransfer: Bool,
        request: Binding<TxActionRequest?>,
        /// Le remboursement s'écrit dans le grand livre de l'appareil, et
        /// nulle part ailleurs : le serveur n'a pas la notion « en prévision ».
        isLocalLedger: Bool = false
    ) -> some View {
        // La même surface pour le menu que pour le tap, et un aperçu qui
        // épouse la ligne plutôt que le rectangle de ses mots.
        contentShape(Rectangle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            // Checked only once it says what it is; an unfiled row is filed first.
            if tx.needsReview, tx.categoryName != nil || tx.isTransfer {
                Button { request.wrappedValue = TxActionRequest(action: .approve, tx: tx) } label: {
                    Label(t("v2.review.approve", "Vérifié"), systemImage: "checkmark.circle")
                }
            }
            Button { request.wrappedValue = TxActionRequest(action: .categorize, tx: tx) } label: {
                Label(t("v2.review.categorize", "Catégoriser"), systemImage: "tag")
            }
            Button { request.wrappedValue = TxActionRequest(action: .rename, tx: tx) } label: {
                Label(t("v2.merchant.title", "Renommer le marchand"), systemImage: "storefront")
            }
            /*
             * L'argent qu'on attend, en une tape.
             *
             * Seulement sur une dépense : un remboursement de remboursement
             * n'existe pas, et un virement interne n'a rien à rendre. La
             * ligne écrite reprend tout de celle-ci — voir
             * `LocalWallet.recordRefund`.
             */
            if isLocalLedger, tx.amount < 0, !tx.isTransfer {
                Button { request.wrappedValue = TxActionRequest(action: .refund, tx: tx) } label: {
                    Label(
                        t("v2.refund.add", "Attendre un remboursement"),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                }
            }
            /*
             * Le détail d'une dépense, que seul le ticket connaît.
             *
             * Sur toutes les lignes du grand livre de l'appareil, y compris
             * une entrée d'argent : un remboursement de frais a lui aussi un
             * justificatif. Voir `ReceiptsSheet`.
             */
            if isLocalLedger {
                Button { request.wrappedValue = TxActionRequest(action: .receipt, tx: tx) } label: {
                    Label(
                        t("v2.receipts.open", "Ticket de caisse"),
                        systemImage: "doc.text.viewfinder"
                    )
                }
            }
            if canTransfer {
                Button { request.wrappedValue = TxActionRequest(action: .transfer, tx: tx) } label: {
                    Label(t("v2.activity.transfer", "Virement interne"), systemImage: "arrow.left.arrow.right")
                }
            }
            Button { request.wrappedValue = TxActionRequest(action: .edit, tx: tx) } label: {
                Label(t("v2.common.edit", "Modifier"), systemImage: "pencil")
            }
            Button {
                UIPasteboard.general.string = Money.string(abs(tx.amount), locale: locale, currency: currency)
            } label: {
                Label(t("v2.menu.copyAmount", "Copier le montant"), systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                request.wrappedValue = TxActionRequest(action: .delete, tx: tx)
            } label: {
                Label(t("v2.common.delete", "Supprimer"), systemImage: "trash")
            }
        }
    }

    /// Attached once per screen: the sheets and the confirmation the menu opens.
    func transactionActions(
        request: Binding<TxActionRequest?>,
        categories: [Category],
        accounts: [Account],
        locale: String,
        currency: String,
        t: Strings,
        onPatch: @escaping (Transaction, TxPatch) async -> Void,
        onDelete: @escaping (Transaction) async -> Void,
        onAttach: @escaping (Transaction, String) async -> Void,
        /// Appelé après l'écriture d'un remboursement : la page affichée ne se
        /// recharge pas d'elle-même, et la ligne doit se voir tout de suite.
        onRefunded: @escaping () async -> Void = {},
        isLocalLedger: Bool = false
    ) -> some View {
        modifier(TransactionActionsHost(
            request: request, categories: categories, accounts: accounts,
            locale: locale, currency: currency, t: t,
            onPatch: onPatch, onDelete: onDelete, onAttach: onAttach,
            onRefunded: onRefunded, isLocalLedger: isLocalLedger
        ))
    }
}

struct TransactionActionsHost: ViewModifier {
    @Binding var request: TxActionRequest?
    let categories: [Category]
    let accounts: [Account]
    let locale: String
    let currency: String
    let t: Strings
    let onPatch: (Transaction, TxPatch) async -> Void
    let onDelete: (Transaction) async -> Void
    let onAttach: (Transaction, String) async -> Void
    var onRefunded: () async -> Void = {}
    /// See `AddTransactionSheet.isLocalLedger`: the edit sheet offers two rows
    /// only the phone's own ledger can honour.
    var isLocalLedger = false

    @State private var sheet: TxActionRequest?
    /// Ce que le grand livre propose pour la ligne en cours de classement.
    @State private var hints: [Category] = []

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                request = nil
                switch new.action {
                case .approve:
                    Task { await onPatch(new.tx, TxPatch(approve: true)) }
                case .delete:
                    // Sans confirmation : la suppression est douce et la
                    // corbeille des Réglages la reprend (LocalLedger.restore).
                    Task { await onDelete(new.tx) }
                case .refund:
                    Task {
                        guard let store = LocalStore.shared else { return }
                        do {
                            try LocalWallet.recordRefund(store: store, of: new.tx)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                        await onRefunded()
                    }
                default:
                    sheet = new
                }
            }
            .sheet(item: $sheet) { pending in
                sheetContent(pending)
            }
    }

    @ViewBuilder
    private func sheetContent(_ pending: TxActionRequest) -> some View {
        let tx = pending.tx
        switch pending.action {
        case .categorize:
            CategoryPicker(
                categories: categories,
                selected: tx.categoryName,
                t: t,
                onPick: { id in Task { await onPatch(tx, TxPatch(categoryId: .some(id))) } },
                hints: hints
            )
            .task { hints = CategoryHint.categories(for: tx, in: categories) }
        case .rename:
            MerchantNameSheet(
                key: MerchantNames.key(tx.payee),
                bankLabel: PayeeText.clean(tx.payee),
                t: t,
                categoryEmoji: tx.categoryEmoji
            )
        case .transfer:
            AttachTransferSheet(
                transaction: tx,
                accounts: accounts,
                locale: locale,
                currency: currency,
                t: t,
                onAttach: { accountId in await onAttach(tx, accountId) },
                // Chosen from a menu that already offered "Catégoriser".
                onSpending: {}
            )
        case .edit:
            // The same sheet that adds one — see `AddTransactionSheet`.
            AddTransactionSheet(
                accounts: accounts,
                categories: categories,
                localeTag: locale,
                currency: currency,
                t: t,
                editing: tx,
                onPatch: { patch in await onPatch(tx, patch) },
                isLocalLedger: isLocalLedger
            )
        case .receipt:
            ReceiptsSheet(tx: tx, locale: locale, currency: currency, t: t)
        case .approve, .delete, .refund:
            EmptyView()
        }
    }
}
