import SwiftUI
import UserNotifications

/// How to have every Apple Pay payment land in Florin the moment it happens.
///
/// The action exists (`RecordPaymentIntent`), but an automation cannot be
/// shipped with an app or shared by link — each person builds their own in
/// Shortcuts. Nor does a shared shortcut help: outside a Transaction
/// automation, Shortcuts hands over its input as plain text, without the
/// amount and merchant the action needs. So this is the recipe, in the words
/// Shortcuts itself uses.
///
/// Laid out to be followed with the other app open: what it does in three
/// pictures, whether it already works, then one line per step with the words
/// to tap in bold, and the way into Shortcuts pinned where the thumb is. No
/// full stops and no second lines — these are labels, not paragraphs.
struct WalletGuideSheet: View {
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsAllowed: Bool?
    @State private var lastPayment: (payee: String, day: Date)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    flow
                    if let lastPayment { activeBadge(lastPayment) }
                    setup
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(t("v2.wallet.guide.title", "Paiements Apple Pay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.settings.tint, floor: true) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await refreshPermission()
            lastPayment = Self.latestPayment()
        }
    }

    // MARK: - What it does

    private var hero: some View {
        Text(t("v2.wallet.guide.hero", "Vos paiements, dès la caisse"))
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Florin.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// Pay, it waits under "upcoming", the bank confirms it — three pictures
    /// instead of the paragraph that said so.
    private var flow: some View {
        HStack(alignment: .top, spacing: 0) {
            flowStep("creditcard.fill", t("v2.wallet.guide.flowPay", "Vous payez"))
            flowArrow
            flowStep("clock.fill", t("v2.wallet.guide.flowUpcoming", "En prévision"))
            flowArrow
            flowStep("checkmark.seal.fill", t("v2.wallet.guide.flowBank", "Confirmé"))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .florinSurface()
    }

    private func flowStep(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Florin.accent)
                .frame(width: 44, height: 44)
                .background(Florin.accent.opacity(0.16), in: Circle())
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var flowArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Florin.text3)
            .padding(.top, 16)
    }

    /// Proof it works: the last payment the automation recorded.
    private func activeBadge(_ payment: (payee: String, day: Date)) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Florin.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("v2.wallet.guide.active", "C'est actif"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Florin.text)
                Text(t(
                    "v2.wallet.guide.lastPayment", "Dernier paiement : {payee}, {day}",
                    ["payee": PayeeText.humanize(payment.payee),
                     "day": DayLabel.string(payment.day, locale: t.localeTag, t: t).lowercased()]
                ))
                .font(.system(size: 13))
                .foregroundStyle(Florin.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .florinSurface(tint: Florin.positive)
    }

    // MARK: - Setting it up

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.wallet.guide.howTo", "Dans Raccourcis"))
            RowGroup {
                step(1, t("v2.wallet.guide.step1", "**Automatisation** → **+**"))
                Hairline()
                step(2, t("v2.wallet.guide.step2", "**Transaction** → cochez vos cartes"))
                Hairline()
                step(3, t("v2.wallet.guide.step3", "**Exécuter immédiatement**"))
                Hairline()
                step(4, t("v2.wallet.guide.step4", "Action **Ajouter une opération à venir**"))
                Hairline()
                step(5, t("v2.wallet.guide.step5", "Reliez à **Entrée du raccourci**")) {
                    VStack(alignment: .leading, spacing: 6) {
                        mapping(t("v2.wallet.guide.fieldAmount", "Montant"),
                                t("v2.wallet.guide.walletAmount", "Montant"))
                        mapping(t("v2.wallet.guide.fieldMerchant", "Marchand"),
                                t("v2.wallet.guide.walletMerchant", "Commerçant"))
                    }
                }
                Hairline()
                step(6, t("v2.wallet.guide.step6", "Décochez **Afficher lors de l'exécution**")) {
                    notificationStatus
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        step(number, text) { EmptyView() }
    }

    private func step<Extra: View>(
        _ number: Int, _ text: String, @ViewBuilder extra: () -> Extra
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Florin.accent, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Self.markdown(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// "Montant ← Montant": the action's field on the left, what Wallet hands
    /// over on the right, the way the two sit in Shortcuts.
    private func mapping(_ field: String, _ source: String) -> some View {
        HStack(spacing: 8) {
            Text(field)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: "arrow.left")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Florin.text3)
            Text(source)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Florin.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Florin.accent.opacity(0.16), in: Capsule())
        }
    }

    @ViewBuilder
    private var notificationStatus: some View {
        if let allowed = notificationsAllowed {
            HStack(spacing: 8) {
                Image(systemName: allowed ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(allowed ? Florin.positive : Florin.warn)
                Text(allowed
                    ? t("v2.wallet.guide.notifyOn", "Notifications autorisées")
                    : t("v2.wallet.guide.notifyOff", "Notifications désactivées"))
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.text2)
                if !allowed {
                    Button(t("v2.wallet.guide.notifyAsk", "Autoriser")) {
                        Task {
                            _ = await BackgroundRefresh.requestPermission()
                            await refreshPermission()
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Florin.accent)
                }
            }
        }
    }

    // MARK: - Going there

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label(t("v2.wallet.guide.openShortcuts", "Ouvrir Raccourcis"), systemImage: "arrow.up.forward.app")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Florin.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Reading

    /// Bold where the string says `**…**` — the words to look for on screen.
    private static func markdown(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }

    private func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .authorized || status == .provisional
    }

    /// The last payment an automation recorded, settled by the bank or not.
    private static func latestPayment() -> (payee: String, day: Date)? {
        guard let store = LocalStore.shared,
              let row = try? store.database.query(
                  """
                  SELECT payee, occurred_at FROM transactions
                  WHERE source = ? ORDER BY created_at DESC LIMIT 1
                  """,
                  [.text(LocalWallet.source)]
              ).first,
              let payee = row.string("payee"),
              let iso = row.string("occurred_at")
        else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        guard let day = f.date(from: String(iso.prefix(10))) else { return nil }
        return (payee, day)
    }
}
