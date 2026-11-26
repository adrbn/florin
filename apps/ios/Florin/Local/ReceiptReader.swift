import Foundation
import FoundationModels
import UIKit
import Vision

/*
 * Lire un ticket de caisse avec ce que le téléphone sait faire seul.
 *
 * Deux étages maison faisaient ce travail, et chacun avait son plafond. La
 * reconnaissance de texte rend des blocs sans ordre de lecture, donc
 * `ReceiptOCR` les regroupait par bande horizontale pour recoller « nom …
 * prix » : un ticket penché de deux degrés, une caisse qui imprime serré, et
 * le prix se rattache à la ligne voisine — l'article qu'il chiffrait
 * disparaît. Puis `ReceiptParser` décidait ce qui est un achat avec une
 * regex de fin de ligne et quatre-vingt-dix mots interdits écrits à la main
 * en quatre langues, une liste qui ne connaîtra jamais la caisse suivante.
 *
 * iOS 26 remplace les deux, sur l'appareil et sans un octet de réseau :
 *
 *  - `RecognizeDocumentsRequest` fait l'analyse de mise en page. Ce qu'il
 *    rend est déjà dans l'ordre de lecture, donc le regroupement maison n'a
 *    plus lieu d'être — c'est la couche qui cassait le plus souvent.
 *  - Le modèle embarqué lit cette transcription et rend les articles
 *    directement. Il sait qu'une ligne « TOTALE » n'est pas un achat sans
 *    qu'on le lui ait écrit, et dans une langue qu'aucune liste ne prévoit.
 *
 * Ni la photo ni la transcription ne quittent l'appareil : c'était la
 * condition. `ProductNames` ne change pas pour autant — c'est lui qui
 * traduit « AUR PROV VALP DOP » en provolone, chez un modèle distant, et
 * seulement si une clé est posée dans les réglages.
 *
 * Le repli est le chemin d'avant, entier. Un iPhone sans Apple Intelligence,
 * un modèle encore en train de se télécharger, une réponse refusée par les
 * garde-fous : le ticket se lit comme hier, et rien ne le dit à l'écran
 * parce qu'il n'y a rien à faire de cette information.
 */
enum ReceiptReading {
    /// Un ticket lu : la photo qu'on garde, le texte qu'on garde, les achats.
    struct Page {
        let thumbnail: Data?
        let text: String
        let items: [ReceiptParser.Item]
    }

    static func read(_ image: UIImage, total: Double?) async -> Page {
        let page = ReceiptOCR.upright(image)
        let thumbnail = ReceiptOCR.thumbnail(page)
        if #available(iOS 26.0, *), let read = await Modern.read(page, total: total) {
            return Page(thumbnail: thumbnail, text: read.text, items: read.items)
        }
        let lines = (try? ReceiptOCR.lines(from: page)) ?? []
        return Page(
            thumbnail: thumbnail,
            text: lines.joined(separator: "\n"),
            items: ReceiptParser.items(from: lines, total: total)
        )
    }
}

@available(iOS 26.0, *)
private enum Modern {
    /*
     * Ce qu'on demande au modèle, et la forme exacte de la réponse.
     *
     * Une sortie guidée plutôt qu'un texte à redécouper : le modèle ne rend
     * pas une phrase dont on extrairait des nombres, il rend des articles.
     * C'est la différence entre lui faire confiance et le contraindre.
     */
    @Generable
    struct Basket {
        @Guide(description: "Les articles achetés, dans l'ordre du ticket")
        let items: [Purchase]
    }

    @Generable
    struct Purchase {
        @Guide(description: "Le nom de l'article tel qu'imprimé sur le ticket, sans le prix")
        let label: String
        @Guide(description: "Le prix payé pour cette ligne, positif, dans la devise du ticket")
        let amount: Double
    }

    private static let instructions = """
    Tu lis des tickets de caisse dans n'importe quelle langue.

    Rends UNIQUEMENT les articles achetés, un par ligne du ticket.

    N'est pas un article, et ne doit jamais être rendu : un total, un \
    sous-total, la TVA, le net à payer, le moyen de paiement, l'espèce \
    rendue, les points de fidélité, l'arrondi, l'en-tête du magasin, son \
    adresse, la date, le numéro de caisse, les mentions légales.

    Quand une ligne de quantité précède ou suit un article (« 2 x 4,80 »), \
    l'article vaut le prix de la ligne, pas celui d'une pièce.

    Quand le nom et le prix sont imprimés sur deux lignes, c'est un seul \
    article.

    Recopie le nom tel qu'il est imprimé, abréviations comprises. Ne le \
    traduis pas, ne le développe pas, n'invente aucun article absent du \
    ticket.
    """

    static func read(_ image: UIImage, total: Double?) async -> (text: String, items: [ReceiptParser.Item])? {
        guard let text = await transcript(of: image), !text.isEmpty else { return nil }
        guard let items = await purchases(in: text, total: total) else { return nil }
        return (text, items)
    }

    /*
     * La transcription, dans l'ordre où un œil la lirait.
     *
     * Sans correction linguistique : une caisse abrège, et « PROV » corrigé
     * en « PROVENCE » est un article perdu. Les langues sont déclarées plutôt
     * que devinées — un ticket romain de quinze lignes ne donne pas assez de
     * matière pour que la détection automatique tranche, et elle tranche
     * quand même.
     */
    private static func transcript(of image: UIImage) async -> String? {
        guard let page = image.cgImage else { return nil }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.recognitionLanguages = [
            Locale.Language(identifier: "fr-FR"),
            Locale.Language(identifier: "it-IT"),
            Locale.Language(identifier: "en-US"),
        ]
        let handler = ImageRequestHandler(page, orientation: .up)
        guard let document = try? await handler.perform(request).first else { return nil }
        return document.document.text.transcript
    }

    /*
     * Le modèle rend ce qu'il veut ; ce qu'on garde, on le vérifie.
     *
     * Un prix nul, un prix qui dépasse à lui seul le montant débité, un nom
     * vide : aucun de ces trois-là n'est un achat, quoi qu'en dise le
     * modèle. Et l'arbitre final ne change pas — c'est l'arithmétique de
     * `ReceiptParser.reconciled`, puis l'écart au montant de la banque que
     * la feuille affiche en « reste à détailler ». Le modèle a remplacé la
     * lecture, pas le contrôle.
     */
    private static func purchases(in text: String, total: Double?) async -> [ReceiptParser.Item]? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        guard let answer = try? await session.respond(
            to: "Voici le ticket :\n\n\(text)",
            generating: Basket.self,
            options: GenerationOptions(temperature: 0)
        ) else { return nil }
        let ceiling = total.map { abs($0) + 0.005 }
        let items = answer.content.items.compactMap { purchase -> ReceiptParser.Item? in
            let label = purchase.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = abs(purchase.amount)
            guard !label.isEmpty, amount > 0 else { return nil }
            if let ceiling, amount > ceiling { return nil }
            return ReceiptParser.Item(label: label, amount: amount)
        }
        // Un ticket dont il ne reste rien n'est pas une lecture : mieux vaut
        // laisser le chemin d'avant essayer que d'enregistrer un panier vide.
        guard !items.isEmpty else { return nil }
        return ReceiptParser.reconciled(items, total: total)
    }
}
