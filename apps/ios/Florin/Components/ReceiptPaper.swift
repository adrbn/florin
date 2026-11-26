import SwiftUI

/*
 * Un ticket de caisse a une forme, et c'est la moitié de ce qu'il dit.
 *
 * Les articles tenaient dans une carte arrondie comme toutes les autres
 * cartes de l'app : juste, lisible, et impossible à distinguer d'une liste
 * d'opérations. Or un ticket n'est pas une liste — c'est une bande de papier
 * thermique, déchirée en haut et en bas, dont les prix sont alignés au
 * millimètre parce qu'une caisse imprime en chasse fixe. Lui rendre cette
 * forme ne décore rien : on reconnaît ce qu'on regarde avant de l'avoir lu.
 *
 * Le papier prend la couleur du thème plutôt qu'un beige dessiné à la main.
 * Les cinq palettes de Florin n'ont pas le même fond, et un ticket crème sur
 * l'Ardoise serait une tache ; ce qui fait le papier ici, c'est la découpe et
 * la chasse fixe, pas la teinte.
 */
struct ReceiptPaper<Content: View>: View {
    /// Rejoué quand cette valeur change : un ticket qui vient d'être lu
    /// reçoit son éclat, les autres restent tranquilles.
    var sweep: AnyHashable?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Florin.surface, in: ReceiptEdge())
            .overlay(ReceiptEdge().stroke(Florin.text.opacity(0.07), lineWidth: 1))
            .modifier(PaperSweep(trigger: sweep))
            .clipShape(ReceiptEdge())
    }
}

/*
 * La déchirure, en haut et en bas seulement.
 *
 * Les côtés d'un ticket sont nets — c'est la bobine qui les coupe — et seuls
 * les bords arrachés sont dentelés. Dentelés aux deux bouts, pas à un seul :
 * un ticket détaché d'un rouleau l'est en haut comme en bas, et n'en denteler
 * qu'un donne un morceau de papier à en-tête.
 *
 * Le nombre de dents se déduit de la largeur, jamais fixé : à nombre constant
 * elles s'étirent avec l'écran et un iPad affiche des créneaux.
 */
struct ReceiptEdge: Shape {
    var tooth: CGFloat = 12
    var depth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(2, Int((rect.width / tooth).rounded()))
        let step = rect.width / CGFloat(count)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + depth))
        for notch in 0 ..< count {
            path.addLine(to: CGPoint(x: rect.minX + step * (CGFloat(notch) + 0.5), y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + step * CGFloat(notch + 1), y: rect.minY + depth))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        for notch in stride(from: count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: rect.minX + step * (CGFloat(notch) + 0.5), y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + step * CGFloat(notch), y: rect.maxY - depth))
        }
        path.closeSubpath()
        return path
    }
}

/*
 * Un éclat qui passe une fois, et ne revient pas.
 *
 * Une bande claire en biais qui traverse le papier : c'est le reflet d'une
 * vitre qu'on incline, et il dit « ceci vient d'arriver » sans une ligne de
 * texte. Une seule fois — un reflet qui boucle devient une animation de
 * chargement, et l'écran se met à clignoter pendant qu'on lit des prix.
 *
 * Clair sur fond sombre, sombre sur fond clair : `plusLighter` sur du blanc
 * ne fait rien du tout, et la Papier n'aurait jamais eu son reflet.
 */
private struct PaperSweep: ViewModifier {
    let trigger: AnyHashable?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let width = geo.size.width
                let band = max(70, width * 0.3)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, glint, .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: band, height: geo.size.height * 2.2)
                    .rotationEffect(.degrees(18))
                    .blendMode(scheme == .dark ? .plusLighter : .multiply)
                    .offset(x: phase * (width + band) - band / 2)
                    .frame(width: width, height: geo.size.height, alignment: .leading)
                    .clipped()
            }
            .allowsHitTesting(false)
        }
        .task(id: trigger) {
            guard trigger != nil, !reduceMotion else { return }
            phase = -0.6
            withAnimation(.easeOut(duration: 0.95)) { phase = 1.6 }
        }
    }

    private var glint: Color {
        scheme == .dark ? .white.opacity(0.22) : .black.opacity(0.06)
    }
}

/*
 * Les pointillés qui mènent le nom jusqu'à son prix.
 *
 * Sur un ticket c'est la chasse fixe qui tient la colonne ; à l'écran les
 * noms n'ont pas tous la même longueur et l'œil perd la ligne entre « thé
 * vert bio » et son montant. Les points font le pont, et c'est la convention
 * qu'on lit sur un menu depuis toujours.
 */
struct ReceiptLeader: View {
    var body: some View {
        Rule()
            .stroke(
                Florin.text3.opacity(0.7),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1.6, 3.4])
            )
            .frame(height: 1)
            .frame(minWidth: 10)
            .padding(.bottom, 3)
    }
}

/// Un filet en tirets : ce que la caisse imprime entre les articles et le
/// total. Plus long que les points d'un guide, pour qu'on les distingue.
struct ReceiptRule: View {
    var body: some View {
        Rule()
            .stroke(
                Florin.text.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
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
 * Le papier qui sort de la caisse pendant qu'on lit la photo.
 *
 * La lecture prend deux ou trois secondes — l'analyse de mise en page, puis
 * le modèle — et un rond qui tourne ne dit pas ce qui se passe. Une bande qui
 * se remplit de lignes grises sous une ligne de balayage dit « on est en
 * train de lire ce papier », ce qui est exactement le cas.
 */
struct ReceiptPrinting: View {
    let label: String
    @State private var scan: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ReceiptPaper {
            VStack(alignment: .leading, spacing: 11) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Florin.text2)
                    .textCase(.uppercase)
                ForEach(0 ..< 5, id: \.self) { row in
                    HStack(spacing: 10) {
                        bar(width: [0.52, 0.38, 0.61, 0.3, 0.45][row])
                        Spacer(minLength: 0)
                        bar(width: 0.14)
                    }
                }
            }
            .padding(.horizontal, Florin.gutter)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { scanline }
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                scan = 1
            }
        }
    }

    private func bar(width: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Florin.text.opacity(0.1))
                .frame(width: geo.size.width * width, height: 9)
        }
        .frame(height: 9)
    }

    /// Sous la ligne, le papier est « lu » : c'est le dégradé qui le dit,
    /// pas un trait seul, qui ressemblerait à une rayure.
    private var scanline: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [Florin.accent.opacity(0), Florin.accent.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 46)
            .offset(y: scan * max(0, geo.size.height - 46))
        }
        .allowsHitTesting(false)
    }
}
