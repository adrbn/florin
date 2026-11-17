import ContactsUI
import SwiftUI
import UIKit

/*
 * Un contact, et pas le carnet d'adresses.
 *
 * `CNContactPickerViewController` ne demande AUCUNE permission, et c'est tout
 * son intérêt ici : la feuille tourne hors du processus de l'app, on y tape un
 * contact, et l'app reçoit celui-là — rien d'autre n'est lu, rien n'est copié,
 * aucune alerte ne s'affiche. L'autre voie, `CNContactStore.requestAccess`,
 * ouvre le carnet entier contre une permission, pour un seul service de plus :
 * proposer des noms pendant qu'on tape. Ce n'est pas ce que vaut la promesse
 * de l'app.
 *
 * Ce qui en ressort reste chez nous : le nom et la photo sont recopiés dans
 * les réglages du marchand (voir `MerchantLogos`), comme une image choisie
 * dans la photothèque. Florin ne garde donc aucun lien vers le carnet, et ne
 * le rouvrira jamais tout seul.
 */
struct ContactPicker: UIViewControllerRepresentable {
    /// Le nom complet tel que Contacts l'écrit, et sa photo s'il en a une.
    var onPick: (String, UIImage?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let onPick: (String, UIImage?) -> Void

        init(onPick: @escaping (String, UIImage?) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            /*
             * Demander si la clé est là avant de la lire, toujours.
             *
             * Lire une propriété que la feuille n'a pas rapportée lève une
             * exception Objective-C — que Swift ne rattrape pas, donc l'app
             * tombe. C'est la feuille qui décide ce qu'elle rapporte, et rien
             * ne lui impose la photo : un contact sans vignette, ou une
             * feuille qui ne l'a pas chargée, doit rendre le nom seul.
             */
            var image: UIImage?
            if contact.isKeyAvailable(CNContactThumbnailImageDataKey),
               let data = contact.thumbnailImageData {
                image = UIImage(data: data)
            }
            if image == nil, contact.isKeyAvailable(CNContactImageDataKey),
               let data = contact.imageData {
                image = UIImage(data: data)
            }
            onPick(
                CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                image
            )
        }
    }
}
