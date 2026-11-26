import CoreMotion
import SwiftUI

/*
 * Le papier d'un ticket de caisse, et la lumière qui tombe dessus.
 *
 * Un rectangle gris avec une dent de scie dessinée au vecteur se lit comme
 * une icône de ticket, jamais comme un ticket : il n'a ni fibre, ni creux,
 * ni reflet, et rien n'y bouge quand la main bouge. La matière est donc
 * calculée par pixel dans `Paper.metal`, et la seule chose que SwiftUI a
 * encore à faire ici est de lui donner sa taille et son ton.
 *
 * Partagé par les deux habillages. La version précédente n'avait été câblée
 * que dans l'habillage classique : sur le thème Éditorial, le seul morceau
 * qui atteignait l'écran était l'écran de chargement, d'où un ticket déchiré
 * pendant la lecture suivi d'une liste plate. Un composant qu'un seul des
 * deux chemins appelle n'est pas un composant, c'est une branche morte.
 */
struct ReceiptPaper<Content: View>: View {
    /// À 0 la feuille est plate : c'est ce qu'il faut derrière une vignette
    /// photo, où une ombre de pli passerait pour une tache sur l'image.
    var bend: Double = 1
    /// Change la découpe sans changer le reste : deux tickets l'un sous
    /// l'autre déchirés au même endroit se voient immédiatement.
    var seed: Double = 0
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    /// Le ton du papier, pris sur la palette et poussé d'un cran hors du fond.
    ///
    /// Jamais un beige écrit en dur : les cinq palettes de Florin n'ont pas le
    /// même fond et une feuille crème sur l'Ardoise serait une tache. Ce qui
    /// fait le papier est la fibre et le creux, pas la teinte.
    private var tone: Color {
        Florin.surface
    }

    var body: some View {
        content.background {
            GeometryReader { geo in
                Rectangle()
                    .fill(ShaderLibrary.thermalPaper(
                        .float2(geo.size.width, geo.size.height),
                        .color(tone),
                        .float(Float(PaperLight.shared.position)),
                        .float(Float(bend))
                    ))
                    .colorEffect(ShaderLibrary.tornEdge(
                        .float2(geo.size.width, geo.size.height),
                        .float(10),
                        .float(Float(seed))
                    ))
                    /*
                     * Deux ombres, pas une.
                     *
                     * Une seule ombre large fait flotter la feuille à dix
                     * centimètres au-dessus de l'écran. Ce qui pose un objet
                     * sur une surface, c'est la ligne noire et serrée juste
                     * sous lui ; la grande ne fait que la profondeur.
                     */
                    .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.16), radius: 12, y: 6)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.40 : 0.10), radius: 1.5, y: 1)
            }
        }
    }
}

/*
 * D'où vient la lumière, d'après l'appareil lui-même.
 *
 * Un reflet qui traverse tout seul est une animation : on la voit une fois,
 * on la reconnaît la deuxième, elle gêne la troisième. Un reflet qui suit
 * l'inclinaison du téléphone n'est pas une animation du tout — c'est une
 * surface, et c'est la seule façon qu'a un écran plat de faire croire à une
 * matière. Le coût tient dans la ligne : le gyroscope à 30 Hz et une valeur
 * publiée seulement quand elle a bougé d'un centième.
 */
@MainActor
@Observable
final class PaperLight {
    static let shared = PaperLight()

    /// De 0 (reflet au bord gauche) à 1 (au bord droit).
    private(set) var position: Double = 0.5

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var watchers = 0

    private init() {}

    /// Compté, parce que plusieurs tickets sont à l'écran en même temps et
    /// que le dernier qui disparaît doit pouvoir éteindre le gyroscope.
    func watch() {
        watchers += 1
        guard watchers == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let roll = data?.attitude.roll else { return }
            // Un quart de tour de chaque côté couvre toute la largeur : au
            // delà, personne ne regarde plus son téléphone.
            let next = min(1, max(0, 0.5 + roll / (.pi / 2)))
            guard abs(next - self.position) > 0.01 else { return }
            self.position = next
        }
    }

    func release() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { motion.stopDeviceMotionUpdates() }
    }
}

extension View {
    /// À poser sur l'écran qui montre des tickets, pas sur chaque ticket.
    func litByTilt() -> some View {
        onAppear { PaperLight.shared.watch() }
            .onDisappear { PaperLight.shared.release() }
    }
}

/// Les pointillés entre un article et son prix.
struct ReceiptLeader: View {
    var body: some View {
        Rule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [1.6, 3.4]))
            .foregroundStyle(Florin.text.opacity(0.22))
            .frame(height: 1)
    }
}

/// Le trait de séparation imprimé par la caisse.
struct ReceiptRule: View {
    var body: some View {
        Rule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(Florin.text.opacity(0.18))
            .frame(height: 1)
    }
}

struct Rule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/*
 * Pendant que ça lit.
 *
 * La version précédente posait cinq barres grises et une ligne de balayage
 * fluo sur du papier déchiré — un écran de chargement plus chargé que le
 * résultat qu'il annonce, et le seul morceau de tout ce travail qui soit
 * arrivé sur l'écran du thème Éditorial. Il ne reste que ce qu'une caisse
 * fait vraiment : une bande qui sort, et son mot.
 */
struct ReceiptPrinting: View {
    let label: String
    @State private var out = false

    var body: some View {
        ReceiptPaper(bend: 0.6) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Florin.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
        }
        // La bande sort de la fente. `scaleEffect` plutôt qu'une hauteur
        // animée : une hauteur qui part de zéro fait sauter tout ce qui est
        // en dessous à chaque image, et on n'anime pas vers `nil`.
        .scaleEffect(y: out ? 1 : 0.04, anchor: .top)
        .opacity(out ? 1 : 0)
        .task { withAnimation(.easeOut(duration: 0.45)) { out = true } }
    }
}
