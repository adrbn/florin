import SwiftUI
import UserNotifications

/// How to have every Apple Pay payment land in Florin the moment it happens.
///
/// The action exists (`RecordPaymentIntent`), but an automation cannot be
/// shipped with an app or shared by link — each person builds their own in
/// Shortcuts. This is the recipe, in the words Shortcuts itself uses, with a
/// way into Shortcuts and, once one is published, a ready-made shortcut that
/// saves wiring the amount and the merchant by hand.
struct WalletGuideSheet: View {
    let t: Strings

    /// A shortcut that already carries the action with Amount and Merchant
    /// wired, shared from iCloud. Nil until one is published; the button that
    /// uses it stays hidden until then.
    static let readyShortcut: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationsAllowed: Bool?

    private var steps: [String] {
        [
            t("v2.wallet.guide.step1", "Dans Raccourcis, ouvrez l'onglet Automatisation et touchez +."),
            t("v2.wallet.guide.step2", "Choisissez « Transaction », cochez vos cartes, puis « Exécuter immédiatement »."),
            t("v2.wallet.guide.step3", "Partez d'une automatisation vide et ajoutez l'action Florin « Ajouter une opération à venir »."),
            t("v2.wallet.guide.step4", "Montant : Entrée du raccourci → Montant. Marchand : Entrée du raccourci → Commerçant."),
            t("v2.wallet.guide.step5", "Désactivez « Afficher lors de l'exécution » : Florin vous prévient lui-même."),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stepList
                    notificationRow
                    actions
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .task { await refreshPermission() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Florin.accent)
            Text(t(
                "v2.wallet.guide.lead",
                "Chaque paiement par carte peut arriver dans Florin à l'instant où vous payez, dans « en prévision »."
            ))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Florin.text)
            .fixedSize(horizontal: false, vertical: true)
            Text(t(
                "v2.wallet.guide.settle",
                "Quand la banque enregistre le paiement, son opération prend la place de celle-ci, avec sa catégorie."
            ))
            .font(.system(size: 13.5))
            .foregroundStyle(Florin.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: t("v2.wallet.guide.howTo", "Une fois, dans Raccourcis"))
            RowGroup {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 22, height: 22)
                            .background(Florin.accent, in: Circle())
                        Text(step)
                            .font(.system(size: 14.5))
                            .foregroundStyle(Florin.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    /// Whether Florin may speak for the automation — the point of step 5.
    @ViewBuilder
    private var notificationRow: some View {
        if let allowed = notificationsAllowed {
            HStack(spacing: 11) {
                Image(systemName: allowed ? "bell.badge.fill" : "bell.slash")
                    .font(.system(size: 15))
                    .foregroundStyle(allowed ? Florin.positive : Florin.warn)
                Text(allowed
                    ? t("v2.wallet.guide.notifyOn", "Florin peut vous prévenir à chaque paiement.")
                    : t("v2.wallet.guide.notifyOff", "Florin n'a pas encore le droit de vous prévenir."))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Florin.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !allowed {
                    Button(t("v2.wallet.guide.notifyAsk", "Autoriser")) {
                        Task {
                            _ = await BackgroundRefresh.requestPermission()
                            await refreshPermission()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Florin.accent)
                }
            }
            .padding(14)
            .florinSurface()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let link = Self.readyShortcut {
                Button { openURL(link) } label: {
                    Label(t("v2.wallet.guide.addShortcut", "Ajouter le raccourci prêt à l'emploi"),
                          systemImage: "plus.square.on.square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Florin.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            } label: {
                Label(t("v2.wallet.guide.openShortcuts", "Ouvrir Raccourcis"), systemImage: "arrow.up.forward.app")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Self.readyShortcut == nil ? .black : Florin.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Self.readyShortcut == nil
                            ? AnyShapeStyle(Florin.accent) : AnyShapeStyle(Florin.surface2),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .authorized || status == .provisional
    }
}
