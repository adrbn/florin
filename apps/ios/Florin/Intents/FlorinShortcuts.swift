import AppIntents

/*
 * Les phrases que Siri écoute, et le raccourci qu'on voit sans l'avoir créé.
 *
 * Une action `AppIntent` seule n'existe que dans l'app Raccourcis, et il faut
 * l'y chercher puis se fabriquer un raccourci pour en faire quoi que ce soit.
 * C'est ce qui manquait : les trois actions de Florin étaient là depuis le
 * début sans qu'on puisse en dire une à voix haute.
 *
 * Ce que ce fournisseur ajoute, c'est l'autre moitié — des phrases prêtes,
 * offertes dans Spotlight et reconnues par Siri sans configuration.
 *
 * Trois choses à savoir, apprises à la dure :
 *
 * 1. Chaque phrase DOIT contenir `\(.applicationName)`. Sans le nom de l'app,
 *    Siri n'a aucun moyen de savoir à qui s'adresse « combien il me reste ».
 *    Le nom compte aussi ses synonymes déclarés par l'app.
 *
 * 2. Les phrases se traduisent dans `AppShortcuts.xcstrings` et NULLE PART
 *    ailleurs : le catalogue doit porter ce nom-là, et ses clés sont les
 *    phrases anglaises avec `${applicationName}` à la place de
 *    l'interpolation. Une langue sans traduction n'obtient aucune phrase —
 *    le raccourci existe, mais muet.
 *
 * 3. Les phrases suivent la langue de SIRI, pas celle de l'app ni celle du
 *    téléphone. Quelqu'un dont Siri parle anglais et l'app français dira la
 *    phrase en anglais et lira la réponse en français ; c'est voulu, la
 *    réponse porte un montant et suit donc la devise.
 */
struct FlorinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LeftToSpendIntent(),
            phrases: [
                "How much is left in \(.applicationName)",
                "What is left to spend in \(.applicationName)",
                "Ask \(.applicationName) what is left this month",
            ],
            shortTitle: LocalizedStringResource(
                "intent.left.short", defaultValue: "Left this month", table: "Intents"
            ),
            systemImageName: "wallet.bifold"
        )
        AppShortcut(
            intent: NetWorthIntent(),
            phrases: [
                "What is my net worth in \(.applicationName)",
                "Ask \(.applicationName) for my net worth",
            ],
            shortTitle: LocalizedStringResource(
                "intent.worth.short", defaultValue: "Net worth", table: "Intents"
            ),
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        /*
         * Celle qui écrit est là aussi, mais en dernier.
         *
         * Elle demande un montant et un marchand, donc Siri les réclame l'un
         * après l'autre — c'est long, et l'automatisation Wallet fait déjà le
         * travail toute seule à la caisse. Elle reste utile pour ce que la
         * carte ne voit pas : des espèces, un virement entre amis.
         */
        AppShortcut(
            intent: RecordPaymentIntent(),
            phrases: [
                "Add a payment to \(.applicationName)",
                "Record an expense in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "intent.payment.short", defaultValue: "Add a payment", table: "Intents"
            ),
            systemImageName: "plus.circle"
        )
    }
}
