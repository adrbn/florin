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
    case approve, categorize, rename, transfer, edit, delete
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
        request: Binding<TxActionRequest?>
    ) -> some View {
        contextMenu {
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
        onAttach: @escaping (Transaction, String) async -> Void
    ) -> some View {
        modifier(TransactionActionsHost(
            request: request, categories: categories, accounts: accounts,
            locale: locale, currency: currency, t: t,
            onPatch: onPatch, onDelete: onDelete, onAttach: onAttach
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

    @State private var sheet: TxActionRequest?
    @State private var deleting: Transaction?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, new in
                guard let new else { return }
                request = nil
                switch new.action {
                case .approve:
                    Task { await onPatch(new.tx, TxPatch(approve: true)) }
                case .delete:
                    deleting = new.tx
                default:
                    sheet = new
                }
            }
            .sheet(item: $sheet) { pending in
                sheetContent(pending)
            }
            .alert(
                t("v2.activity.deleteConfirm", "Supprimer cette opération ?"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
            ) {
                Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                    if let tx = deleting { Task { await onDelete(tx) } }
                    deleting = nil
                }
                Button(t("v2.common.cancel", "Annuler"), role: .cancel) { deleting = nil }
            } message: {
                Text(deleting.map { PayeeText.humanize($0.payee) } ?? "")
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
                onPick: { id in Task { await onPatch(tx, TxPatch(categoryId: .some(id))) } }
            )
        case .rename:
            MerchantNameSheet(
                key: MerchantNames.key(tx.payee),
                bankLabel: PayeeText.clean(tx.payee),
                t: t
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
            TransactionEditor(tx: tx, locale: locale, currency: currency, t: t) { patch in
                await onPatch(tx, patch)
            }
        case .approve, .delete:
            EmptyView()
        }
    }
}
