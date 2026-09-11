import SwiftUI

/*
 * The balance spins while the bank is asked, like a slot machine's reels.
 *
 * Pull-to-refresh held the whole screen down under a spinner for as long as
 * the bank took, then laid "À jour" over the search field. The pull now
 * springs straight back and the figure it would change carries the wait: its
 * digits roll through random values, and once the sync is done they stop one
 * by one, left to right, on the real figure — new or unchanged.
 *
 * Same number of digits throughout, so the figure never jumps in width. It
 * spins for at least `minimumSpin` even when the answer is instant: a flicker
 * reads as a glitch, not as a refresh. With Reduce Motion it only dims.
 */
struct SlotAmount: View {
    let value: Double
    let spinning: Bool
    let locale: String
    let currency: String
    var size: CGFloat = 52

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reels: Double?
    @State private var spinStart: Date?

    private static let tick: Duration = .milliseconds(90)
    private static let lockTick: Duration = .milliseconds(110)
    private static let minimumSpin: TimeInterval = 0.9

    var body: some View {
        HeroAmount(value: reels ?? value, locale: locale, currency: currency, size: size)
            .contentTransition(.numericText())
            .opacity(reduceMotion && spinning ? 0.5 : 1)
            .task(id: spinning) {
                guard !reduceMotion else { return }
                if spinning {
                    spinStart = Date()
                    while !Task.isCancelled {
                        roll(locked: 0)
                        try? await Task.sleep(for: Self.tick)
                    }
                } else if let start = spinStart {
                    spinStart = nil
                    await settle(since: start)
                } else {
                    // Left mid-settle (another tab, say): back on the real figure,
                    // never frozen on a random one.
                    reels = nil
                }
            }
    }

    /// Keeps spinning to the minimum, then stops each reel in turn.
    private func settle(since start: Date) async {
        while Date().timeIntervalSince(start) < Self.minimumSpin {
            roll(locked: 0)
            try? await Task.sleep(for: Self.tick)
            if Task.isCancelled { return }
        }
        let count = Self.digits(of: value).count
        for locked in 1...max(count, 1) {
            roll(locked: locked)
            try? await Task.sleep(for: Self.lockTick)
            if Task.isCancelled { return }
        }
        withAnimation(.snappy(duration: 0.2)) { reels = nil }
    }

    /// The real figure's first `locked` digits, random ones after them.
    private func roll(locked: Int) {
        let real = Self.digits(of: value)
        var out = ""
        for (i, digit) in real.enumerated() {
            if i < locked {
                out.append(digit)
            } else {
                // A leading zero would drop a digit and shrink the figure.
                out.append(String(Int.random(in: i == 0 ? 1...9 : 0...9)).first!)
            }
        }
        let cents = Double(out) ?? 0
        withAnimation(.snappy(duration: 0.14)) {
            reels = (value < 0 ? -cents : cents) / 100
        }
    }

    /// The figure in cents, as digits: 8 718,18 → "871818".
    private static func digits(of value: Double) -> [Character] {
        Array(String(Int((abs(value) * 100).rounded())))
    }
}
