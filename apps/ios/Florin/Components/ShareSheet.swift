import SwiftUI
import UIKit

/// The system share sheet.
///
/// SwiftUI's `ShareLink` would do for a URL, but it wants the item at the
/// moment the view is built, and the export does not exist until the button is
/// pressed. This takes the file it is given.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
