import SwiftUI

/*
 * Comptes, dans le langage Éditorial.
 *
 * L'onglet a disparu de la barre : on arrive ici depuis la pile de cartes de
 * l'accueil, et le chevron du bandeau ramène d'où l'on vient. L'écran n'a donc
 * pas de titre centré à défendre — il a un chiffre, une courbe, une
 * répartition au trait, et des comptes en lignes séparées par des filets.
 *
 * Tout ce qu'il sait des comptes vient de `AccountsLogic`, partagé avec
 * l'ancien écran : les groupes, l'échelle des barres, le renommage et la
 * suppression y sont écrits une fois.
 */
struct EditorialAccounts: View {
    @ObservedObject var model: OverviewModel
    let onBack: () -> Void
    let onOpenSettings: () -> Void

    @State private var drill: ActivityRoute?
    @State private var showNet = true
    @State private var addingAccount = false
    @State private var renaming: Account?
    @State private var deleting: Account?
    @Environment(\.scenePhase) private var scenePhase

    private var t: Strings { model.overview?.t ?? .device }
    private var local: Bool { model.base.scheme == "florin-local" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let data = model.overview {
                    figure(data).edEnter()
                    curve(data).edEnter()
                    allocation(data).edEnter()
                    groups(data)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Florin.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, Ed.gutter)
            .padding(.top, 10)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(Florin.bg)
        .refreshable { await model.load() }
        .task { await model.onForeground() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.onForeground() } }
        }
        .fullScreenCover(item: $drill) { target in
            AccountDetailScreen(model: model, route: target)
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet(onSaved: { Task { await model.load(showSpinner: false) } })
                .edSheet()
        }
        .sheet(item: $renaming) { account in
            AccountEditSheet(
                account: account, t: t,
                balance: AccountsLogic.editableBalance(account, local: local)
            ) { name, icon, balance in
                AccountsLogic.commitEdit(account, name: name, icon: icon, balance: balance)
                await model.load(showSpinner: false)
            }
            .edSheet()
        }
        .alert(
            t("v2.accounts.deleteConfirm", "Supprimer ce compte ?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { account in
            Button(t("v2.common.delete", "Supprimer"), role: .destructive) {
                deleting = nil
                AccountsLogic.delete(account)
                Task { await model.load(showSpinner: false) }
            }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) { deleting = nil }
        } message: { account in
            Text(t(
                "v2.accounts.deleteBody",
                "{name} et toutes ses opérations seront supprimés de cet appareil. S'il était synchronisé, le lien avec votre banque s'arrête avec lui — rien ne change du côté de la banque.",
                ["name": account.name]
            ))
        }
    }

    // MARK: Le bandeau

    private var header: some View {
        EdHeader {
            EdIconButton(
                symbol: "chevron.left", label: t("v2.common.back", "Retour"), action: onBack
            )
        } trailing: {
            HStack(spacing: 2) {
                if local {
                    EdIconButton(
                        symbol: "plus", label: t("v2.accounts.add", "Ajouter un compte")
                    ) { addingAccount = true }
                }
                EdIconButton(
                    symbol: "arrow.trianglehead.2.clockwise",
                    label: t("v2.common.refresh", "Actualiser"),
                    spinning: model.syncing
                ) {
                    Task { await model.sync(confirmCurrent: false) }
                }
                .disabled(model.syncing || !(model.overview?.bankSyncConfigured ?? false))
                EdIconButton(
                    symbol: "line.3.horizontal",
                    label: t("v2.settings.title", "Réglages"),
                    action: onOpenSettings
                )
            }
            .padding(.trailing, -10)
        }
    }

    // MARK: Le chiffre

    /// Net ou brut, sur le même mot : l'étiquette dit lequel, et le chiffre
    /// roule de l'un à l'autre plutôt que de se remplacer.
    private func figure(_ data: Overview) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(EdMotion.spring) { showNet.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                EdPill(text: showNet
                    ? t("v2.overview.netWorth", "Patrimoine")
                    : t("v2.overview.gross", "Brut"))
                EdAmount(
                    text: Money.string(
                        showNet ? data.netWorth.net : data.netWorth.gross,
                        locale: data.localeTag, currency: data.currency
                    ),
                    size: 48,
                    value: showNet ? data.netWorth.net : data.netWorth.gross
                )
                Text(showNet
                    ? t("v2.accounts.count", "{count} comptes",
                        ["count": AccountsLogic.visible(data).count])
                    : t("v2.overview.debt", "Dettes") + " " + Money.string(
                        data.netWorth.liability, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text2)
                    .hiddenWhenPrivate()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
        .padding(.top, 24)
    }

    /// La courbe, au trait et sans sol — voir `NetWorthChart`, qui laisse
    /// tomber son dégradé dans ce thème.
    private func curve(_ data: Overview) -> some View {
        NetWorthChart(
            points: Array(
                (showNet ? (data.netSeries ?? data.series) : (data.grossSeries ?? data.series))
                    .filter { $0.projected != true }
                    .suffix(200)
            ),
            height: 108,
            selection: .constant(nil),
            animationKey: showNet ? "net" : "gross",
            tint: Florin.text
        )
        .padding(.top, 18)
        .allowsHitTesting(false)
    }

    // MARK: La répartition

    /*
     * Une barre, pas un anneau.
     *
     * Le donut de l'ancien écran est une forme décorative avec un trou au
     * milieu ; la maquette n'en a pas. Une barre empilée dit la même chose sur
     * une ligne, avec trois encres grises et des filets entre les parts, et
     * laisse la place à une légende lisible juste dessous.
     */
    @ViewBuilder
    private func allocation(_ data: Overview) -> some View {
        let slices = AccountsLogic.slices(data, t: t)
        let total = slices.reduce(0) { $0 + $1.value }
        if total > 0 {
            VStack(alignment: .leading, spacing: 14) {
                EdSection(text: t("v2.overview.allocation", "Répartition"))
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            Rectangle()
                                .fill(ink(index))
                                .frame(width: max(2, geo.size.width * slice.value / total - 2))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                VStack(spacing: 0) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                        if index > 0 { EdRule() }
                        HStack(spacing: 10) {
                            Circle().fill(ink(index)).frame(width: 8, height: 8)
                            Text(slice.label)
                                .font(.system(size: 15))
                                .foregroundStyle(Florin.text)
                            Spacer(minLength: 8)
                            Text(Money.string(
                                slice.value, locale: data.localeTag,
                                currency: data.currency, decimals: false
                            ))
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Florin.text)
                            .hiddenWhenPrivate()
                            Text("\(Int((slice.value / total * 100).rounded()))%")
                                .font(.system(size: 13))
                                .foregroundStyle(Florin.text3)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.top, 30)
        }
    }

    /// Trois encres du plus foncé au plus clair : la part la plus grosse est
    /// la plus appuyée, et aucune n'est l'accent — qui reste à l'alerte.
    private func ink(_ index: Int) -> Color {
        Florin.series[min(index * 2, Florin.series.count - 1)]
    }

    // MARK: Les comptes

    private func groups(_ data: Overview) -> some View {
        let scale = AccountsLogic.assetTotal(data)
        return ForEach(AccountsLogic.buckets(data, t: t), id: \.title) { group in
            VStack(alignment: .leading, spacing: 10) {
                EdSection(
                    text: group.title,
                    trailing: Money.string(
                        group.total, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    )
                )
                VStack(spacing: 0) {
                    ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                        if index > 0 { EdRule() }
                        row(account, data, scale: scale)
                    }
                }
            }
            .padding(.top, 30)
            .edEnter()
        }
    }

    private func row(_ account: Account, _ data: Overview, scale: Double) -> some View {
        Button {
            drill = ActivityRoute(accountId: account.id, title: account.name)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(account.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money.string(
                        account.displayValue, locale: data.localeTag,
                        currency: data.currency, decimals: false
                    ))
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(account.isLoan ? Florin.text2 : Florin.text)
                    .hiddenWhenPrivate()
                }
                // La part de ce compte dans le plus gros avoir — la même
                // échelle pour toutes les lignes, sinon la barre ne compare
                // rien.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Florin.text.opacity(0.10))
                        Capsule()
                            .fill(account.isLoan ? Florin.negative : Florin.text)
                            .frame(
                                width: max(
                                    2,
                                    geo.size.width
                                        * (scale > 0 ? abs(account.displayValue) / scale : 0)
                                )
                            )
                    }
                }
                .frame(height: 3)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.edPress)
        .contextMenu {
            if local {
                Button {
                    renaming = account
                } label: {
                    Label(t("v2.accounts.rename", "Renommer"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleting = account
                } label: {
                    Label(t("v2.common.delete", "Supprimer"), systemImage: "trash")
                }
            }
        }
    }
}
