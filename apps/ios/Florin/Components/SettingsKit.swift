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
            if let symbol {
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

    private var tint: Color { destructive ? Florin.negative : Florin.accent }
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
