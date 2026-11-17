import MapKit
import SwiftUI

/*
 * Ce qu'un point sur la carte vaut, quand on le touche.
 *
 * Une épingle seule ne dit rien de plus que « j'y suis allé ». Ce qu'on
 * veut savoir en la touchant, c'est depuis quand on y va, combien de
 * fois, et ce qu'on y laisse en moyenne — trois chiffres qu'un total
 * seul ne donne pas, et qui changent la lecture : quarante euros chez
 * l'un en deux ans ne se compare pas à quarante chez l'autre en un mois.
 *
 * Rien n'est calculé ici : tout vient de `LocalPlaces.all`, qui a déjà
 * fait la somme pour la liste. Une fiche qui recompte dirait un jour un
 * autre chiffre que la ligne qui l'a ouverte.
 */
struct MerchantPlaceDetail: View {
    let place: LocalPlaces.Place
    let locale: String
    let currency: String
    let t: Strings

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    head
                    facts
                    map
                    actions
                }
                .padding(.horizontal, Florin.gutter)
                .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("v2.common.close", "Fermer")) { dismiss() }
                }
            }
        }
        .presentationBackground { Backdrop(tint: TabRoute.analysis.tint, floor: true) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $editing, onDismiss: { dismiss() }) {
            MerchantPlaceSheet(payee: place.key, name: place.name, t: t)
        }
    }

    private var head: some View {
        VStack(spacing: 8) {
            let face = MerchantLogos.shared.face(forKey: place.key)
            Bubble(label: place.key, chosen: face?.emoji, size: 54, logo: face?.logo)
            Text(Money.string(place.spent, locale: locale, currency: currency))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Florin.text)
            Text(t("v2.places.visits", "{count} passages", ["count": place.visits]))
                .font(.system(size: 13.5))
                .foregroundStyle(Florin.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var facts: some View {
        RowGroup {
            fact(t("v2.places.firstVisit", "Première visite"), day(place.first))
            Hairline()
            fact(t("v2.places.lastVisit", "Dernière visite"), day(place.last))
            Hairline()
            fact(
                t("v2.places.average", "Panier moyen"),
                place.visits > 0
                    ? Money.string(place.spent / Double(place.visits),
                                   locale: locale, currency: currency)
                    : "—"
            )
            Hairline()
            // Le libellé que la banque emploie, parce que c'est lui qui
            // décide ce que l'épingle couvre — voir `MerchantPlaceSheet`.
            fact(t("v2.places.identity", "Identité"), place.key.uppercased())
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(Florin.text2)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Florin.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 11)
    }

    private var map: some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        ), interactionModes: []) {
            Marker(place.name, coordinate: place.coordinate)
                .tint(Florin.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }

    private var actions: some View {
        SheetAction(
            label: t("v2.places.edit", "Modifier l'épingle"),
            symbol: "mappin.and.ellipse", prominent: true
        ) { editing = true }
    }

    private func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DayLabel.string(date, locale: locale, t: t)
    }
}
