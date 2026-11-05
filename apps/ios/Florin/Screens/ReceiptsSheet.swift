import PhotosUI
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
    /// La photo gardée, décodée une fois par chargement : la vue se redessine
    /// à chaque frappe de la feuille, pas le fichier.
    @State private var photos: [String: UIImage] = [:]
    @State private var viewing: Photo?
    @State private var scanning = false
    /// Les jetons que rend la photothèque : des images à charger, pas des
    /// images.
    @State private var picked: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var failure: String?
    /// Ce qu'on a compris des libellés, relu une fois par chargement — la
    /// vue se redessine souvent, la base pas.
    @State private var meanings: [String: ProductNames.Reading] = [:]
    @State private var explaining = false

    private var items: [LocalReceipts.Item] { receipts.flatMap(\.items) }
    /// Les libellés qu'on ne sait pas encore lire.
    private var puzzling: [String] {
        items.map(\.label).filter { meanings[ProductNames.key($0)] == nil }
    }
    private var remainder: Double {
        LocalReceipts.unexplained(total: tx.amount, items: items)
    }

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    /*
     * Deux habillages, une seule feuille — comme `TransactionDetailSheet`,
     * d'où l'on arrive, et `AddTransactionSheet`.
     */
    var body: some View {
        if editorial {
            plumbed(editorialShell)
        } else {
            plumbed(classicShell)
        }
    }

    /// La tuyauterie des deux : le chargement, la photo en grand, le scanner.
    private func plumbed(_ shell: some View) -> some View {
        shell
            .presentationDetents([.large])
            .task { load() }
            .fullScreenCover(item: $viewing) { photo in
                viewer(photo)
            }
            .fullScreenCover(isPresented: $scanning) {
                ReceiptScanner { images in
                    scanning = false
                    read(images)
                }
                .ignoresSafeArea()
            }
    }

    private var classicShell: some View {
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
                        if !puzzling.isEmpty, !reading { understand }
                        if let failure {
                            Text(failure)
                                .font(.system(size: 13))
                                .foregroundStyle(Florin.negative)
                        }
                        scan
                        importer
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
    }

    // MARK: - L'habillage éditorial

    /*
     * Ce que le papier dit, dans la typographie de la maison.
     *
     * L'habillage classique posait tout dans une carte unique : la photo, les
     * articles, le total et — au milieu du chemin de lecture, juste sous le
     * total — un « Supprimer ce ticket » pleine largeur en rouge. On lisait
     * donc son panier en passant chaque fois le doigt au-dessus de la seule
     * action irréversible de la page.
     *
     * Ici le sujet est le commerçant, en héros, parce que le montant est déjà
     * le héros de la fiche d'où l'on arrive : le répéter en grand dirait deux
     * fois la même chose et pas une fois ce qu'on vient chercher. La date et
     * le montant tiennent en une ligne sous le nom, les articles s'alignent
     * entre filets sans carte, la suppression descend au pied de son ticket,
     * discrète et nommée, et « Scanner » devient l'action pleine de la page.
     */
    private var editorialShell: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                edTitle
                if reading {
                    progress.padding(.horizontal, Ed.gutter)
                }
                if receipts.isEmpty, !reading {
                    edEmpty
                } else {
                    ForEach(receipts) { receipt in
                        edReceipt(receipt)
                    }
                    if abs(remainder) > 0.005 { edRemainder }
                }
                if !puzzling.isEmpty, !reading { edUnderstand }
                if let failure { edFailure(failure) }
                edActions
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { edHeader.background(Florin.bg) }
        .background(Florin.bg)
    }

    private var edHeader: some View {
        HStack(spacing: 2) {
            EdPill(text: t("v2.receipts.title", "Ticket de caisse"))
            Spacer(minLength: 8)
            EdIconButton(symbol: "xmark", label: t("v2.common.close", "Fermer")) {
                dismiss()
            }
            // La cible de 44 pt déborde la gouttière ; c'est l'encre qui
            // s'aligne sur elle, pas le cadre.
            .padding(.trailing, -10)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var edTitle: some View {
        VStack(alignment: .leading, spacing: 9) {
            EdHero(text: PayeeText.title(tx.payee, category: tx.categoryName), size: edTitleSize)
            HStack(spacing: 7) {
                Text(DayLabel.string(tx.day, locale: locale, t: t))
                    .font(.system(size: 14))
                    .foregroundStyle(Florin.text2)
                Text("·")
                    .font(.system(size: 14))
                    .foregroundStyle(Florin.text3)
                AmountText(
                    value: tx.amount, locale: locale, currency: currency,
                    signed: true, tone: .auto, size: 14
                )
            }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.bottom, 22)
    }

    /// Il descend quand il s'allonge : « Forno » et « Gruppo Negozi Srl » ne
    /// tiennent pas dans le même corps, et un nom coupé n'est plus un nom.
    private var edTitleSize: CGFloat {
        switch PayeeText.title(tx.payee, category: tx.categoryName).count {
        case ...10: return 56
        case 11...17: return 44
        default: return 34
        }
    }

    private var edEmpty: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(t("v2.receipts.empty", "Aucun ticket pour cette opération."))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Florin.text)
            Text(t(
                "v2.receipts.emptyHint",
                "Photographie le ticket : Florin en lit les articles et leurs prix, et les retrouve ensuite dans la recherche."
            ))
            .font(.system(size: 14))
            .foregroundStyle(Florin.text2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.bottom, 24)
    }

    private func edReceipt(_ receipt: LocalReceipts.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = photos[receipt.id], let path = receipt.imagePath {
                Button {
                    viewing = Photo(id: receipt.id, image: image, path: path)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Ed.largeCard, style: .continuous)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(9)
                        }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Ed.gutter)
                .padding(.bottom, 14)
            }
            if receipt.items.isEmpty {
                Text(t("v2.receipts.nothingRead", "Aucun article lu sur cette photo."))
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text2)
                    .padding(.horizontal, Ed.gutter)
                    .padding(.vertical, 12)
            } else {
                EdRule()
                ForEach(receipt.items) { item in
                    edItem(item)
                    EdRule()
                }
                HStack {
                    Text(t("v2.receipts.receiptTotal", "Total du ticket"))
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                    Spacer(minLength: 8)
                    AmountText(
                        value: receipt.total, locale: locale, currency: currency,
                        tone: .muted, size: 14
                    )
                }
                .padding(.horizontal, Ed.gutter)
                .padding(.vertical, 12)
            }
            /*
             * Au pied du ticket, et pas pleine largeur.
             *
             * Une rangée rouge sur toute la colonne pèse autant qu'un article
             * et se touche aussi facilement — or elle efface une photo qu'on
             * ne reprendra pas, le papier étant à la poubelle. Elle garde son
             * mot, parce qu'un pictogramme seul ne dit pas ce qu'il efface,
             * et se range à droite, hors du chemin de lecture des prix.
             */
            Button(role: .destructive) {
                guard let store = LocalStore.shared else { return }
                try? LocalReceipts.delete(store: store, receiptId: receipt.id)
                load()
                onChanged?()
            } label: {
                Text(t("v2.receipts.delete", "Supprimer ce ticket"))
                    .font(.system(size: 13))
                    .foregroundStyle(Florin.negative)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Ed.gutter)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 20)
    }

    /*
     * Le nom clair devant, l'imprimé derrière, et la catégorie avec lui.
     *
     * « CRUDO MOZZARELLA VI » est ce que la caisse a su écrire en vingt-quatre
     * caractères, pas un nom d'article. Le nom compris prend la ligne, et
     * l'imprimé reste dessous puisque c'est lui qui est sur le papier et
     * contre lui qu'on vérifie une lecture douteuse. La catégorie se range sur
     * la même ligne que l'imprimé : elle était calculée et jetée.
     */
    private func edItem(_ item: LocalReceipts.Item) -> some View {
        let reading = meanings[ProductNames.key(item.label)]
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reading?.name ?? item.label)
                    .font(.system(size: 16))
                    .foregroundStyle(Florin.text)
                    .lineLimit(2)
                if let reading {
                    Text([item.label, reading.category]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(value: item.amount, locale: locale, currency: currency, size: 16)
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.vertical, 13)
    }

    /// Ce que les articles n'expliquent pas. Pas une erreur : un ticket qui
    /// manque, ou une ligne que la photo n'a pas rendue.
    private var edRemainder: some View {
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
        .padding(.horizontal, Ed.gutter)
        .padding(.vertical, 13)
        .background(Florin.text.opacity(0.04))
        .padding(.bottom, 20)
    }

    private var edUnderstand: some View {
        SheetAction(
            label: explaining
                ? t("v2.receipts.understanding", "Lecture des articles…")
                : t("v2.receipts.understand", "Comprendre les articles"),
            symbol: "sparkles"
        ) {
            Task { await explain() }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.bottom, 14)
        .disabled(explaining || reading)
        .opacity(explaining || reading ? 0.5 : 1)
    }

    private func edFailure(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Florin.negative)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Ed.gutter)
            .padding(.bottom, 14)
    }

    /// Scanner est l'action de la page ; importer est le cas où le papier
    /// n'est plus là, donc un mot sous le bouton plutôt qu'un second bouton.
    private var edActions: some View {
        VStack(spacing: 4) {
            SheetAction(
                label: receipts.isEmpty
                    ? t("v2.receipts.scan", "Scanner un ticket")
                    : t("v2.receipts.scanMore", "Scanner un autre ticket"),
                symbol: "doc.viewfinder",
                prominent: true, large: true
            ) {
                failure = nil
                scanning = true
            }
            .disabled(reading)
            .opacity(reading ? 0.5 : 1)

            PhotosPicker(selection: $picked, maxSelectionCount: 4, matching: .images) {
                Text(t("v2.receipts.import", "Importer une photo"))
                    .font(.system(size: 14))
                    .foregroundStyle(Florin.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
            }
            .disabled(reading)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await read(chosen: items) }
            }
        }
        .padding(.horizontal, Ed.gutter)
        .padding(.top, 4)
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
            /*
             * La photo, et pas seulement ce qu'on en a lu.
             *
             * Elle était gardée depuis le début — redressée et compressée par
             * `ReceiptOCR.thumbnail` — mais rien ne la montrait : une ligne
             * mal lue ne se vérifiait donc contre rien. Elle ouvre en grand,
             * d'où elle se partage et s'enregistre.
             */
            if let image = photos[receipt.id], let path = receipt.imagePath {
                Button {
                    viewing = Photo(id: receipt.id, image: image, path: path)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 148)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
                Hairline()
            }
            if receipt.items.isEmpty {
                line(t("v2.receipts.nothingRead", "Aucun article lu sur cette photo."), nil)
            } else {
                ForEach(Array(receipt.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline() }
                    itemLine(item)
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

    /*
     * Ce que la caisse a voulu dire, quand on le sait.
     *
     * « AUR PROV VALP DOP » n'est pas un nom d'article, c'est ce qui tient en
     * vingt-quatre caractères. Le nom clair prend la première ligne et le
     * libellé imprimé reste dessous : c'est lui qui est sur le papier, et
     * c'est contre lui qu'on vérifie une lecture douteuse.
     */
    private func itemLine(_ item: LocalReceipts.Item) -> some View {
        let reading = meanings[ProductNames.key(item.label)]
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading?.name ?? item.label)
                    .font(.system(size: 15))
                    .foregroundStyle(Florin.text)
                    .lineLimit(2)
                if reading != nil {
                    Text(item.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Florin.text2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(value: item.amount, locale: locale, currency: currency)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 11)
    }

    /// Déchiffrer les libellés qui résistent. Discret et facultatif : sans
    /// clé d'API rien ne part, et le ticket reste lisible tel quel.
    private var understand: some View {
        Button {
            Task { await explain() }
        } label: {
            Label(
                explaining
                    ? t("v2.receipts.understanding", "Lecture des articles…")
                    : t("v2.receipts.understand", "Comprendre les articles"),
                systemImage: "sparkles"
            )
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .tint(Florin.text2)
        .buttonStyle(PressScale())
        .disabled(explaining || reading)
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
        .tint(Florin.control)
        .buttonStyle(PressScale())
        .disabled(reading)
    }

    /*
     * Un ticket qu'on n'a plus sous la main.
     *
     * Le scanner veut le papier devant l'objectif, et c'est le cas courant.
     * Mais la photo est parfois déjà prise — le ticket est resté sur la table,
     * la commande est arrivée par mail, quelqu'un d'autre l'a photographiée —
     * et il n'y avait alors aucun chemin vers le même traitement. Le
     * sélecteur système le donne sans demander l'accès à la photothèque : il
     * tourne hors de l'app et ne rend que ce qui est choisi.
     */
    private var importer: some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 4, matching: .images) {
            Label(
                t("v2.receipts.import", "Importer une photo"),
                systemImage: "photo.on.rectangle"
            )
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .tint(Florin.text2)
        .disabled(reading)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await read(chosen: items) }
        }
    }

    // MARK: - Lire et ranger

    private func load() {
        guard let store = LocalStore.shared else { return }
        receipts = (try? LocalReceipts.receipts(store: store, transactionId: tx.id)) ?? []
        photos = receipts.reduce(into: [:]) { photos, receipt in
            guard let path = receipt.imagePath,
                  let image = UIImage(contentsOfFile: url(path).path)
            else { return }
            photos[receipt.id] = image
        }
        meanings = (try? ProductNames.known(
            store: store, labels: receipts.flatMap(\.items).map(\.label)
        )) ?? [:]
    }

    /// Demander ce qu'on n'a pas encore compris, et le garder.
    private func explain() async {
        guard let store = LocalStore.shared else { return }
        explaining = true
        failure = nil
        do {
            try await ProductNames.resolve(
                store: store, labels: puzzling, merchant: PayeeText.clean(tx.payee)
            )
        } catch {
            failure = error.localizedDescription
        }
        explaining = false
        load()
    }

    private func url(_ path: String) -> URL {
        guard let store = LocalStore.shared else { return URL(fileURLWithPath: path) }
        return LocalReceipts.url(store: store, path: path)
    }

    /// La photo en grand : lue, partagée, enregistrée.
    private func viewer(_ photo: Photo) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea(edges: .bottom)
            VStack {
                HStack(spacing: 10) {
                    Button { viewing = nil } label: { glyph("xmark") }
                        .accessibilityLabel(t("v2.common.close", "Fermer"))
                    Spacer()
                    // Sortir la photo de l'app : la photothèque pour la garder,
                    // le partage pour l'envoyer. Le système demande lui-même
                    // l'autorisation d'ajout, et un refus ne retire rien — la
                    // photo reste là où elle a toujours été, dans l'app.
                    Button {
                        UIImageWriteToSavedPhotosAlbum(photo.image, nil, nil, nil)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: { glyph("square.and.arrow.down") }
                        .accessibilityLabel(
                            t("v2.receipts.saveToPhotos", "Enregistrer dans Photos")
                        )
                    ShareLink(item: url(photo.path)) { glyph("square.and.arrow.up") }
                }
                .padding(.horizontal, Florin.gutter)
                Spacer()
            }
        }
    }

    /// Un rond sombre sous un symbole : lisible sur n'importe quelle photo.
    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(10)
            .background(.black.opacity(0.45), in: Circle())
    }

    struct Photo: Identifiable {
        let id: String
        let image: UIImage
        let path: String
    }

    /*
     * La reconnaissance est lente — quelques secondes par ticket — et n'a
     * aucune raison de tenir l'écran. Les photos partent donc sur une tâche
     * de fond, et l'écriture revient sur le fil principal où la base est lue.
     */
    /// Les images choisies, chargées une par une puis lues comme un scan.
    private func read(chosen items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            images.append(image)
        }
        read(images)
    }

    private func read(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        reading = true
        Task.detached(priority: .userInitiated) {
            let pages = images.map { image -> (Data?, String, [ReceiptParser.Item]) in
                let lines = (try? ReceiptOCR.lines(from: image)) ?? []
                return (
                    ReceiptOCR.thumbnail(image),
                    lines.joined(separator: "\n"),
                    ReceiptParser.items(from: lines, total: tx.amount)
                )
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
