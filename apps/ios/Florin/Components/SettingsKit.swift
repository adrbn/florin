import SwiftUI

/// The building blocks the settings screen is made of.
///
/// It was a stock `Form`. That gave every row a grey slab, a system separator
/// and a type scale belonging to a different application than the dashboard —
/// and worse, it made actions indistinguishable from labels: a `Button` around
/// plain text renders as body copy, so "Synchroniser les banques" read as a
/// sentence. These are the app's own cards, and an action here looks like one.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Eyebrow(text: title).padding(.horizontal, 4) }

            VStack(spacing: 0) { content }
                .florinSurface()

            if let footer {
                Text(footer)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Florin.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A line that states something, and optionally does something.
struct SettingsRow<Trailing: View>: View {
    let label: String
    var symbol: String?
    /// Present when the row is an action: it gets the accent colour and a
    /// chevron, because that is the whole convention for "this goes somewhere".
    var action: (() -> Void)?
    var destructive = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let content = HStack(spacing: 11) {
            // En éditorial, pas de pictogramme coloré devant chaque ligne :
            // une page de réglages en compte une trentaine, et trente taches
            // orange en colonne répètent trente mots déjà écrits à côté.
            if let symbol, !editorial {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 20)
            }
            Text(label)
                .font(.system(size: 15.5, weight: action == nil ? .regular : .medium))
                .foregroundStyle(action == nil ? Florin.text : tint)
            Spacer(minLength: 8)
            trailing
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
        }
        .padding(.horizontal, Florin.gutter)
        .padding(.vertical, 13)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var editorial: Bool { FlorinPalette.selected == .editorial }

    /*
     * La couleur d'une ligne qui mène quelque part.
     *
     * Ailleurs c'est l'accent, qui est la convention de l'app pour « ceci
     * s'ouvre ». En éditorial l'accent appartient au héros et aux alertes : une
     * ligne qui ouvre un écran s'écrit à l'encre et c'est le chevron qui dit
     * qu'elle s'ouvre. Le destructif garde sa couleur dans les deux — c'est le
     * seul endroit où du rouge est une information, pas une décoration.
     */
    private var tint: Color {
        if destructive { return Florin.negative }
        return editorial ? Florin.text : Florin.accent
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        label: String,
        symbol: String? = nil,
        action: (() -> Void)? = nil,
        destructive: Bool = false
    ) {
        self.init(
            label: label, symbol: symbol, action: action,
            destructive: destructive, trailing: { EmptyView() }
        )
    }
}

/// The grey half of a row: a value, not an action.
struct SettingsValue: View {
    let text: String
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .monospaced(monospaced)
            .foregroundStyle(Florin.text2)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
