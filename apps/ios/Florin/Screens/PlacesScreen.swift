import MapKit
import SwiftUI

/*
 * La carte des marchands — ce que l'argent a visité.
 *
 * Rien n'est géocodé et rien ne sort du téléphone : chaque point vient du
 * GPS de l'appareil, posé pendant qu'on était sur place. Voir
 * `LocalPlaces` pour les deux moments où il peut témoigner.
 *
 * Dézoomer REGROUPE au lieu d'empiler. Une ville tient quarante épingles
 * dont trente se recouvrent, et un tas d'épingles illisibles n'est pas une
 * carte : les points d'une même zone deviennent un seul rond qui porte ce
 * qu'on y a dépensé. La taille des mailles suit la vue — dix mailles en
 * travers de l'écran, quelle que soit l'échelle — donc le regroupement se
 * défait en zoomant, sans seuil à régler.
 */
struct PlacesScreen: View {
    let locale: String
    let currency: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @State private var places: [LocalPlaces.Place] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var span: MKCoordinateSpan?
    @State private var focused: String?

    private var clusters: [Cluster] { Cluster.group(places, span: span) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if places.isEmpty {
                    empty
                } else {
                    map
                    list
                }
            }
            .navigationTitle(t("v2.places.title", "Carte des marchands"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.settings.tint, floor: true) }
        .presentationDetents([.large])
        .task { reload() }
    }

    private func reload() {
        guard let store = LocalStore.shared else { return }
        places = LocalPlaces.all(store: store)
    }

    // MARK: - La carte

    private var map: some View {
        Map(position: $camera) {
            ForEach(clusters) { cluster in
                Annotation(coordinate: cluster.center) {
                    bubble(cluster)
                } label: {
                    EmptyView()
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            span = context.region.span
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, Florin.gutter)
        .padding(.bottom, 14)
    }

    private func bubble(_ cluster: Cluster) -> some View {
        let lit = cluster.places.contains { $0.key == focused }
        return VStack(spacing: 3) {
            Text(Money.compact(cluster.spent, locale: locale, currency: currency))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Florin.onAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(lit ? Florin.text : Florin.accent)
                )
            if cluster.places.count == 1 {
                Text(cluster.places[0].name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Florin.text)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(Florin.surface.opacity(0.85)))
            } else {
                Text("\(cluster.places.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Florin.text2)
            }
        }
        .onTapGesture { focus(cluster) }
    }

    private func focus(_ cluster: Cluster) {
        focused = cluster.places.first?.key
        withAnimation {
            camera = .region(
                MKCoordinateRegion(
                    center: cluster.center,
                    span: MKCoordinateSpan(
                        latitudeDelta: max((span?.latitudeDelta ?? 0.05) / 4, 0.002),
                        longitudeDelta: max((span?.longitudeDelta ?? 0.05) / 4, 0.002)
                    )
                )
            )
        }
    }

    // MARK: - La liste

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RowGroup {
                    ForEach(Array(places.enumerated()), id: \.element.key) { index, place in
                        if index > 0 { Hairline() }
                        row(place)
                    }
                }
                .padding(.horizontal, Florin.gutter)

                Text(t(
                    "v2.places.footer",
                    "Chaque point vient du GPS de cet appareil. Aucun nom de marchand n'est envoyé nulle part."
                ))
                .font(.system(size: 12))
                .foregroundStyle(Florin.text3)
                .padding(.horizontal, Florin.gutter + 4)
                .padding(.bottom, 24)
            }
            .padding(.top, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ place: LocalPlaces.Place) -> some View {
        Button {
            focus(Cluster(center: place.coordinate, spent: place.spent, places: [place]))
        } label: {
            HStack(spacing: 12) {
                let face = MerchantLogos.shared.face(forKey: place.key)
                Bubble(label: place.key, chosen: face?.emoji, size: 34, logo: face?.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .lineLimit(1)
                    Text(t(
                        "v2.places.visits", "{count} passages",
                        ["count": place.visits]
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text2)
                }
                Spacer(minLength: 8)
                Text(Money.string(place.spent, locale: locale, currency: currency))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Florin.text)
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Florin.text3)
            Text(t("v2.places.empty", "Aucun lieu encore."))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Florin.text)
            Text(t(
                "v2.places.emptyHint",
                "Chez un marchand, ouvrez son opération et touchez « J'y suis » : son point vaudra pour tout son historique."
            ))
            .font(.system(size: 13))
            .foregroundStyle(Florin.text2)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Florin.gutter + 12)
        .padding(.top, 60)
    }

    // MARK: - Le regroupement

    struct Cluster: Identifiable {
        let center: CLLocationCoordinate2D
        let spent: Double
        let places: [LocalPlaces.Place]
        var id: String { places.map(\.key).joined(separator: "|") }

        /*
         * Dix mailles en travers de l'écran, quelle que soit l'échelle.
         *
         * Un seuil en mètres marcherait à un seul niveau de zoom et serait
         * faux partout ailleurs — c'est la taille à l'ÉCRAN qui décide si
         * deux points se recouvrent, pas leur distance au sol. La maille se
         * déduit donc de la vue, et le regroupement se défait en zoomant
         * sans qu'aucun réglage ne lui dise quand.
         */
        static func group(
            _ places: [LocalPlaces.Place], span: MKCoordinateSpan?
        ) -> [Cluster] {
            let cell = max((span?.latitudeDelta ?? 0.4) / 10, 0.00002)
            var bins: [String: [LocalPlaces.Place]] = [:]
            for place in places {
                let key = "\(Int((place.lat / cell).rounded()))|\(Int((place.lon / cell).rounded()))"
                bins[key, default: []].append(place)
            }
            return bins.values.map { group in
                Cluster(
                    center: CLLocationCoordinate2D(
                        latitude: group.map(\.lat).reduce(0, +) / Double(group.count),
                        longitude: group.map(\.lon).reduce(0, +) / Double(group.count)
                    ),
                    spent: group.map(\.spent).reduce(0, +),
                    places: group.sorted { $0.spent > $1.spent }
                )
            }
            .sorted { $0.spent > $1.spent }
        }
    }
}

extension LocalPlaces.Place {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
