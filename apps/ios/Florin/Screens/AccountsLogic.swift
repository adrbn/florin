import Foundation
import SwiftUI

/*
 * Ce que « la liste des comptes » veut dire, une fois pour les deux écrans.
 *
 * `AccountsScreen` portait ce regroupement, cette échelle de barres et ces
 * deux écritures dans ses méthodes privées. L'écran éditorial montre les mêmes
 * comptes autrement : s'il s'était recopié ces règles, un compte d'un genre
 * nouveau aurait fini par apparaître dans un style et pas dans l'autre, et
 * supprimer un compte aurait laissé sa connexion bancaire derrière lui d'un
 * côté seulement.
 *
 * Rien de visuel ici — c'est la réponse, pas sa mise en page.
 */
enum AccountsLogic {
    struct Bucket {
        let title: String
        let accounts: [Account]
        var total: Double { accounts.reduce(0) { $0 + $1.displayValue } }
    }

    static func visible(_ data: Overview) -> [Account] {
        data.accounts.filter { !$0.isArchived }
    }

    /// Le plus gros avoir, pour que toutes les barres soient à la même échelle —
    /// une barre normalisée ligne par ligne ne dit rien du tout.
    static func assetTotal(_ data: Overview) -> Double {
        visible(data).map { abs($0.displayValue) }.max() ?? 0
    }

    static func buckets(_ data: Overview, t: Strings) -> [Bucket] {
        let all = visible(data)
        let definitions: [(String, String, [String])] = [
            ("v2.accounts.group.checking", "Comptes courants", ["checking", "cash"]),
            ("v2.accounts.group.savings", "Épargne", ["savings"]),
            ("v2.accounts.group.broker", "Investissement", ["broker_cash", "broker_portfolio"]),
            ("v2.accounts.group.loan", "Emprunts", ["loan"]),
        ]
        var used = Set<String>()
        var out = definitions.compactMap { key, fallback, kinds -> Bucket? in
            let matched = all.filter { kinds.contains($0.kind) }
            guard !matched.isEmpty else { return nil }
            matched.forEach { used.insert($0.id) }
            return Bucket(title: t(key, fallback), accounts: matched)
        }
        // Ce que les groupes ne nomment pas doit tout de même apparaître : un
        // genre ajouté plus tard au schéma ne doit pas disparaître de l'écran.
        let rest = all.filter { !used.contains($0.id) }
        if !rest.isEmpty {
            out.append(Bucket(title: t("v2.accounts.group.other", "Autres"), accounts: rest))
        }
        return out
    }

    /// Les trois tranches de la répartition, vides exclues.
    static func slices(_ data: Overview, t: Strings) -> [(label: String, value: Double, color: Color)] {
        [
            (t("v2.overview.cash", "Liquidités"), data.allocation.cash, Florin.series[0]),
            (t("v2.overview.invested", "Investi"), data.allocation.invested, Florin.series[2]),
            (t("v2.overview.debt", "Dettes"), data.allocation.loans, Florin.negative),
        ].filter { $0.1 > 0 }
    }

    /// Le solde n'est modifiable que là où il est à nous : pas sur un compte
    /// que la banque réécrit à chaque sync, pas sur un prêt dont le restant dû
    /// se déduit du contrat, pas sur un portefeuille valorisé par ses titres.
    static func editableBalance(_ account: Account, local: Bool) -> Double? {
        guard local,
              account.isSynced != true,
              !account.isLoan,
              account.kind != "broker_portfolio"
        else { return nil }
        return account.total
    }

    static func commitEdit(_ account: Account, name: String, icon: String, balance: Double?) {
        guard let store = LocalStore.shared, !name.isEmpty else { return }
        try? store.database.run(
            "UPDATE accounts SET name = ?, display_icon = ?, updated_at = datetime('now') WHERE id = ?",
            [.text(name), .text(icon), .text(account.id)]
        )
        if let balance {
            try? LocalHoldings.setBalance(store: store, accountId: account.id, to: balance)
        }
    }

    static func delete(_ account: Account) {
        guard let store = LocalStore.shared else { return }
        /*
         * Parti, avec ses lignes, en une transaction.
         *
         * Archiver laisserait les opérations compter dans les dépenses alors
         * que le compte auquel elles appartiennent est invisible — un solde que
         * personne ne peut montrer. Si quelqu'un demande à supprimer un compte,
         * la réponse honnête est qu'il est supprimé.
         */
        try? store.database.transaction {
            /*
             * Le lien bancaire part avec lui, sinon le compte revient.
             *
             * La sync retrouve un compte par l'uid que la banque lui a donné,
             * et cet uid vivait sur la ligne qu'on supprime. La ligne partie,
             * la sync suivante ne reconnaît rien et réinsère le compte avec ses
             * opérations — supprimer un compte synchronisé avait donc l'air de
             * marcher puis se défaisait tout seul. Mais seulement si aucun autre
             * compte ne roule encore sur cette connexion.
             */
            let connection = try store.database.scalar(
                "SELECT bank_connection_id FROM accounts WHERE id = ?", [.text(account.id)]
            )?.string

            try store.database.run(
                "DELETE FROM transactions WHERE account_id = ?", [.text(account.id)]
            )
            try store.database.run("DELETE FROM accounts WHERE id = ?", [.text(account.id)])

            if let connection {
                let others = try store.database.scalar(
                    "SELECT count(*) FROM accounts WHERE bank_connection_id = ?",
                    [.text(connection)]
                )?.int ?? 0
                if others == 0 {
                    try store.database.run(
                        """
                        DELETE FROM bank_sync_account_results
                         WHERE run_id IN (SELECT id FROM bank_sync_runs WHERE connection_id = ?)
                        """,
                        [.text(connection)]
                    )
                    try store.database.run(
                        "DELETE FROM bank_sync_runs WHERE connection_id = ?", [.text(connection)]
                    )
                    try store.database.run(
                        "DELETE FROM bank_connections WHERE id = ?", [.text(connection)]
                    )
                }
            }
        }
    }
}
