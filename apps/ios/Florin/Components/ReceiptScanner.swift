import SwiftUI
import UIKit
import Vision
import VisionKit

/*
 * Photographier un ticket de caisse, et en lire le texte.
 *
 * Le scanner de documents d'iOS plutôt qu'un appareil photo maison avec un
 * cadre en forme de ticket dessiné dessus : il trouve les bords tout seul,
 * les suit pendant qu'on bouge, redresse la perspective, et enchaîne
 * plusieurs pages dans la même session — c'est-à-dire exactement « on peut le
 * faire plusieurs fois, il peut y en avoir plusieurs ». Un cadre fixe, lui,
 * demande qu'on place le ticket au millimètre et rend une photo de travers.
 */
struct ReceiptScanner: UIViewControllerRepresentable {
    /// Les pages photographiées, déjà redressées, dans l'ordre.
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: VNDocumentCameraViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(
            _: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(
            _: VNDocumentCameraViewController, didFailWithError _: Error
        ) {
            onFinish([])
        }
    }
}

/*
 * Ce que la photo dit, remis en lignes.
 *
 * La reconnaissance rend des blocs de texte, pas des lignes de ticket : sur
 * une caisse, le nom de l'article et son prix sont alignés aux deux bords
 * opposés, donc reconnus séparément. Pris tels quels, aucun bloc ne porte à
 * la fois un nom et un prix et le découpage ne trouve jamais rien.
 *
 * Les blocs sont donc regroupés par bande horizontale — même hauteur à la
 * demi-ligne près — puis remis de gauche à droite. C'est ce regroupement, et
 * non la reconnaissance, qui fait marcher la lecture d'un ticket.
 */
enum ReceiptOCR {
    /// Lent et exact : on scanne un ticket, pas une vidéo. Sans correction
    /// linguistique, qui transformerait les abréviations de caisse en mots.
    static func lines(from image: UIImage) throws -> [String] {
        guard let page = upright(image).cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        try VNImageRequestHandler(cgImage: page, orientation: .up).perform([request])

        let blocks = (request.results ?? []).compactMap { observation -> Block? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return Block(y: box.midY, x: box.minX, height: box.height, text: best.string)
        }
        return group(blocks)
    }

    private struct Block {
        let y: CGFloat
        let x: CGFloat
        let height: CGFloat
        let text: String
    }

    /// L'origine de Vision est en bas à gauche : la première ligne du ticket
    /// est celle dont le `y` est le plus grand.
    private static func group(_ blocks: [Block]) -> [String] {
        let sorted = blocks.sorted { $0.y > $1.y }
        var lines: [[Block]] = []
        for block in sorted {
            // Même bande que la précédente si les deux se chevauchent
            // verticalement pour plus de la moitié de leur hauteur.
            if let last = lines.last?.last,
               abs(last.y - block.y) < max(block.height, last.height) * 0.6 {
                lines[lines.count - 1].append(block)
            } else {
                lines.append([block])
            }
        }
        return lines.map { line in
            line.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
        }
    }

    /// Redressée une fois pour toutes, plutôt que de traduire l'orientation à
    /// chaque usage — la photo est aussi celle qu'on garde.
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        return redraw(image, at: image.size)
    }

    /// La photo telle qu'on la garde : lisible, et pas trois mégaoctets.
    static func thumbnail(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let page = upright(image)
        let side = max(page.size.width, page.size.height)
        guard side > maxSide else { return page.jpegData(compressionQuality: 0.7) }
        let scale = maxSide / side
        let size = CGSize(width: page.size.width * scale, height: page.size.height * scale)
        return redraw(page, at: size).jpegData(compressionQuality: 0.7)
    }

    /// À l'échelle 1 : la photo porte déjà ses pixels, et le facteur d'écran
    /// la triplerait sans rien ajouter.
    private static func redraw(_ image: UIImage, at size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
