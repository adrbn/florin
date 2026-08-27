import SwiftUI

/// A long job, with somewhere to look while it runs and something to read when
/// it stops.
///
/// The import used to report itself by rewriting a settings row — "Import en
/// cours… 1300 opérations" — which turned a list of settings into a progress
/// bar and left nothing at all at the end. A job that touches every account and
/// every transaction deserves to say what it did.
struct TaskSheet: View {
    enum State: Equatable {
        case running(String)
        case success(title: String, detail: String)
        case failure(String)
    }

    let title: String
    let state: State
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Backdrop(tint: TabRoute.accounts.tint).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                switch state {
                case let .running(message):
                    ProgressView()
                        .controlSize(.large)
                        .tint(Florin.accent)
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                case let .success(title, detail):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Florin.positive)
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)

                case let .failure(message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Florin.negative)
                    Text("Ça n'a pas marché")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Florin.text)
                    // The real message, not a friendly replacement for it: the
                    // only person who can act on this is looking at it.
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Florin.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }

                Spacer()

                if case .running = state {
                    Text("Ne fermez pas Florin.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text3)
                        .padding(.bottom, 30)
                } else {
                    Button(action: onDone) {
                        Text("Terminé")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Florin.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Florin.gutter)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isRunning)
    }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
}
