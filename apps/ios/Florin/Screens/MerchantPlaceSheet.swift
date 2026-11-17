import MapKit
import SwiftUI

/*
 * L'épingle d'un marchand — montrée avant d'être écrite.
 *
 * Une tape posait le point en silence, sur le relevé que le téléphone
 * avait sous la main. En ville, entre deux immeubles, ce relevé est faux
 * de cinquante mètres et rien ne le disait : l'épingle atterrissait dans
 * la rue d'à côté, sur un marchand qu'on n'avait jamais vu, et il n'y
 * avait aucun moyen de la reprendre. Un geste sans retour qui se trompe
 * une fois sur trois ne vaut pas mieux que pas de geste du tout.
 *
 * Donc : la carte d'abord, le point au centre, et RIEN n'est écrit tant
 * qu'on ne l'a pas dit. Déplacer la carte déplace le point — c'est la
 * seule correction possible quand le GPS se trompe et qu'on est déjà
 * reparti. « Me localiser » rappelle le relevé frais pour qui est sur
 * place, et « Retirer » défait une épingle d'un coup.
 *
 * Rien ne sort du téléphone, ici non plus : la carte d'Apple ne reçoit
 * aucun nom de marchand, seulement les tuiles de la zone regardée.
 */
struct MerchantPlaceSheet: View {
    let payee: String
    let name: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    /// Le centre de la vue, donc le point qui sera écrit. Il suit la carte en
    /// continu — c'est ce que le viseur promet.
    @State private var center: CLLocationCoordinate2D?
    @State private var pinned = false
    @State private var locating = false
    @State private var failure: String?
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                controls
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.activity.tint, floor: true) }
        .presentationDetents([.large])
        .task { start() }
        .alert(
            t("v2.places.here", "J'y suis"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(t("v2.common.ok", "OK"), role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .confirmationDialog(
            t("v2.places.remove", "Retirer l'épingle"),
            isPresented: $confirmingRemoval, titleVisibility: .visible
        ) {
            Button(t("v2.places.remove", "Retirer l'épingle"), role: .destructive) { remove() }
            Button(t("v2.common.cancel", "Annuler"), role: .cancel) {}
        }
    }

    // MARK: - La carte

    /*
     * Le viseur est fixe, c'est la carte qui bouge.
     *
     * Une épingle qu'on traîne au doigt se cache sous le doigt au moment
     * précis où l'on vise. Posée au centre, elle reste visible tout du long,
     * et la précision ne dépend plus de la taille de la main.
     */
    private var map: some View {
        Map(position: $camera)
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .continuous) { context in
                center = context.region.center
            }
            .overlay {
                Image(systemName: "mappin")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Florin.accent)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    // La pointe de l'épingle est en bas du glyphe : sans ce
                    // décalage, le point visé serait sa tête.
                    .offset(y: -15)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Text(t("v2.places.adjust", "Déplacez la carte : le point est au centre."))
                    .font(.system(size: 12))
                    .foregroundStyle(Florin.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Florin.surface.opacity(0.92)))
                    .padding(.bottom, 12)
            }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            SheetAction(
                label: t("v2.places.save", "Enregistrer ici"),
                symbol: "mappin.and.ellipse", prominent: true, large: true
            ) { save() }
            .disabled(center == nil)
            .opacity(center == nil ? 0.5 : 1)

            HStack(spacing: 10) {
                SheetAction(
                    label: t("v2.places.locate", "Me localiser"),
                    symbol: "location"
                ) { locate() }
                .disabled(locating)
                if pinned {
                    SheetAction(
                        label: t("v2.places.remove", "Retirer l'épingle"),
                        symbol: "mappin.slash", destructive: true
                    ) { confirmingRemoval = true }
                }
            }

            Text(t(
                "v2.places.footer",
                "Chaque point vient du GPS de cet appareil. Aucun nom de marchand n'est envoyé nulle part."
            ))
            .font(.system(size: 12))
            .foregroundStyle(Florin.text3)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    // MARK: - Les gestes

    /// L'épingle existante si elle existe, sinon là où l'on est — et si le
    /// système n'a rien sous la main, on lui demande un relevé frais, ce qui
    /// est aussi le moment où il pose sa question d'autorisation.
    private func start() {
        guard let store = LocalStore.shared else { return }
        pinned = LocalPlaces.pinned(store: store, payee: payee)
        if let known = LocalPlaces.coordinate(store: store, payee: payee) {
            show(known)
        } else if let fix = LocalPlaces.lastKnown {
            show(fix.coordinate)
        } else {
            locate()
        }
    }

    private func show(_ coordinate: CLLocationCoordinate2D) {
        center = coordinate
        camera = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
            )
        )
    }

    private func locate() {
        locating = true
        Task {
            let fix = await PlaceFinder().fix()
            locating = false
            guard let fix else {
                failure = t("v2.places.noFix", "Position indisponible ici.")
                return
            }
            withAnimation { show(fix.coordinate) }
        }
    }

    private func save() {
        guard let store = LocalStore.shared, let center else { return }
        LocalPlaces.set(
            store: store, payee: payee,
            lat: center.latitude, lon: center.longitude, accuracy: 20
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func remove() {
        guard let store = LocalStore.shared else { return }
        LocalPlaces.forget(store: store, payee: payee)
        pinned = false
        dismiss()
    }
}
