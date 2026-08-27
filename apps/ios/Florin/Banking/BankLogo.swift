import SwiftUI

/// A bank's mark in the picker, with something sane when there isn't one.
///
/// Enable Banking gives a `logo` URL for most institutions and nothing for
/// some. A row that sometimes has an image and sometimes has a hole reads as
/// broken, so the fallback is not empty space: it is the bank's initials on a
/// tinted tile, sized and shaped exactly like the image it stands in for.
struct BankLogo: View {
    let bank: Aspsp

    private static let side: CGFloat = 38

    var body: some View {
        Group {
            if let logo = bank.logo, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                            // Most of these marks are dark-on-transparent and
                            // vanish on this background; a white tile is what
                            // the banks' own brand guidelines assume anyway.
                            .background(Color.white)
                    case .failure:
                        initials
                    default:
                        ProgressView().controlSize(.mini)
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var initials: some View {
        ZStack {
            Florin.surface2
            Text(Self.initials(of: bank.name))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Florin.text2)
        }
    }

    /// Up to two initials, skipping the articles that would otherwise make
    /// half the French banks read "LB".
    static func initials(of name: String) -> String {
        let skipped: Set<String> = ["la", "le", "les", "de", "du", "des", "banque", "bank"]
        let words = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !skipped.contains($0.lowercased()) }
        let source = words.isEmpty
            ? name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            : words
        return source.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
