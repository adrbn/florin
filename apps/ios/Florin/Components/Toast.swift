import SwiftUI

/// Liquid Glass where the OS has it, a blur where it does not.
///
/// The app deploys to iOS 17 but is built against the 26 SDK, so the modifier
/// has to be guarded. Everything floating over content — the toast, the sync
/// affordance — goes through here rather than hand-rolling a translucent
/// background, so there is exactly one place to change when the material does.
extension View {
    @ViewBuilder
    func florinGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }
    }
}

enum ToastKind {
    case success
    case failure
    case neutral

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .neutral: return "arrow.trianglehead.2.clockwise"
        }
    }

    var tint: Color {
        switch self {
        case .success: return Florin.positive
        case .failure: return Florin.negative
        case .neutral: return Florin.accent
        }
    }
}

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let kind: ToastKind

    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

/// A capsule that slides down from under the status bar and leaves on its own.
///
/// It replaces a modal alert for sync results. An alert is a stop sign — it
/// takes the screen, demands a tap, and is the wrong weight entirely for "your
/// accounts are up to date". This says the same thing without interrupting, and
/// can be flicked away early.
private struct ToastOverlay: ViewModifier {
    @Binding var message: ToastMessage?
    var duration: TimeInterval = 2.6

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                HStack(spacing: 9) {
                    Image(systemName: message.kind.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(message.kind.tint)
                    Text(message.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Florin.text)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .florinGlass(in: Capsule())
                .padding(.horizontal, 24)
                .offset(y: min(0, dragOffset))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation.height }
                        .onEnded { drag in
                            if drag.translation.height < -12 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    self.message = nil
                                }
                            }
                            dragOffset = 0
                        }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
                .task(id: message.id) {
                    try? await Task.sleep(for: .seconds(duration))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        self.message = nil
                    }
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: message)
    }
}

extension View {
    func florinToast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastOverlay(message: message))
    }
}
