import SwiftUI

/// An SVG `path` `d` string, drawn as a SwiftUI `Shape`.
///
/// Brand marks are the one place where "close enough" is not acceptable — a
/// hand-approximated Octocat is instantly wrong, and SF Symbols has no GitHub
/// or Ko-fi glyph. Rather than ship rasterised PNGs at three densities, the
/// official single-path SVGs are parsed and stroked as real vectors: they scale,
/// they take a tint, and they are byte-for-byte the marks the two projects
/// publish.
///
/// The parser covers the full path grammar (M L H V C S Q T A and their
/// relative forms) rather than only the commands these two paths happen to use,
/// because a partial parser fails silently and draws nonsense.
struct SVGPath: Shape {
    let commands: String
    /// Both marks are authored on a 24×24 canvas.
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / viewBox
        let originX = rect.minX + (rect.width - viewBox * scale) / 2
        let originY = rect.minY + (rect.height - viewBox * scale) / 2

        var scanner = PathScanner(commands)
        var current = CGPoint.zero
        var start = CGPoint.zero
        /// Reflected control point for the shorthand S / T forms.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character = "M"

        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * scale, y: originY + p.y * scale)
        }

        while true {
            if let next = scanner.command() {
                command = next
            } else if !scanner.hasNumber {
                break
            }
            // A repeated parameter set continues the previous command — except
            // after a moveto, where it means lineto.
            let relative = command.isLowercase
            let base = relative ? current : .zero

            switch Character(command.lowercased()) {
            case "m":
                guard let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                current = CGPoint(x: base.x + x, y: base.y + y)
                start = current
                path.move(to: map(current))
                command = relative ? "l" : "L"
                lastCubicControl = nil
                lastQuadControl = nil
            case "l":
                guard let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: map(current))
                lastCubicControl = nil
                lastQuadControl = nil
            case "h":
                guard let x = scanner.number() else { return finish(path) }
                current = CGPoint(x: base.x + x, y: current.y)
                path.addLine(to: map(current))
                lastCubicControl = nil
                lastQuadControl = nil
            case "v":
                guard let y = scanner.number() else { return finish(path) }
                current = CGPoint(x: current.x, y: base.y + y)
                path.addLine(to: map(current))
                lastCubicControl = nil
                lastQuadControl = nil
            case "c":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: map(current), control1: map(c1), control2: map(c2))
                lastCubicControl = c2
                lastQuadControl = nil
            case "s":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                let c1 = lastCubicControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: map(current), control1: map(c1), control2: map(c2))
                lastCubicControl = c2
                lastQuadControl = nil
            case "q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                let c = CGPoint(x: base.x + x1, y: base.y + y1)
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: map(current), control: map(c))
                lastQuadControl = c
                lastCubicControl = nil
            case "t":
                guard let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                let c = lastQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: map(current), control: map(c))
                lastQuadControl = c
                lastCubicControl = nil
            case "a":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(), let largeArc = scanner.number(),
                      let sweep = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return finish(path) }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                appendArc(
                    &path, from: current, to: end, rx: rx, ry: ry,
                    rotation: rotation, largeArc: largeArc != 0, sweep: sweep != 0, map: map
                )
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
            case "z":
                path.closeSubpath()
                current = start
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                return finish(path)
            }
        }

        return finish(path)
    }

    private func finish(_ path: Path) -> Path { path }

    /// Endpoint parameterisation → centre parameterisation, per the SVG spec's
    /// implementation notes, then flattened into cubics.
    private func appendArc(
        _ path: inout Path,
        from: CGPoint,
        to: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        rotation: CGFloat,
        largeArc: Bool,
        sweep: Bool,
        map: (CGPoint) -> CGPoint
    ) {
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, from != to else {
            path.addLine(to: map(to))
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (from.x - to.x) / 2, dy2 = (from.y - to.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        // Scale the radii up if they are too small to span the chord.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coefficient = denominator == 0 ? 0 : sign * (numerator / denominator).squareRoot()
        let cx1 = coefficient * rx * y1 / ry
        let cy1 = -coefficient * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (from.x + to.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (from.y + to.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            guard len > 0 else { return 0 }
            let value = acos(min(1, max(-1, dot / len)))
            return (ux * vy - uy * vx) < 0 ? -value : value
        }

        let start = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var sweepAngle = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        // A cubic approximates a circular arc well below ~90°; split accordingly.
        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        var theta = start
        var point = from
        for _ in 0..<segments {
            let next = theta + delta
            let cosT = cos(theta), sinT = sin(theta)
            let cosN = cos(next), sinN = sin(next)

            func onEllipse(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(
                    x: cx + rx * cosPhi * c - ry * sinPhi * s,
                    y: cy + rx * sinPhi * c + ry * cosPhi * s
                )
            }
            func derivative(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(
                    x: -rx * cosPhi * s - ry * sinPhi * c,
                    y: -rx * sinPhi * s + ry * cosPhi * c
                )
            }

            let end = onEllipse(cosN, sinN)
            let d1 = derivative(cosT, sinT)
            let d2 = derivative(cosN, sinN)
            let c1 = CGPoint(x: point.x + alpha * d1.x, y: point.y + alpha * d1.y)
            let c2 = CGPoint(x: end.x - alpha * d2.x, y: end.y - alpha * d2.y)
            path.addCurve(to: map(end), control1: map(c1), control2: map(c2))

            point = end
            theta = next
        }
    }
}

/// Tokeniser for an SVG `d` string.
///
/// The grammar is looser than it looks: separators are optional, `-` starts a
/// new number without one, and a second `.` does too (`.5.5` is two numbers).
/// Splitting on whitespace and commas silently loses half of a real-world path.
private struct PathScanner {
    private let chars: [Character]
    private var index = 0

    init(_ string: String) { chars = Array(string) }

    private mutating func skipSeparators() {
        while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n"
            || chars[index] == "\t" || chars[index] == "\r" {
            index += 1
        }
    }

    mutating func command() -> Character? {
        skipSeparators()
        guard index < chars.count, chars[index].isLetter else { return nil }
        defer { index += 1 }
        return chars[index]
    }

    var hasNumber: Bool {
        var probe = index
        while probe < chars.count, chars[probe] == " " || chars[probe] == "," { probe += 1 }
        guard probe < chars.count else { return false }
        let c = chars[probe]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        guard index < chars.count else { return nil }

        var text = ""
        var seenDot = false
        var seenDigit = false

        if chars[index] == "-" || chars[index] == "+" {
            text.append(chars[index])
            index += 1
        }
        while index < chars.count {
            let c = chars[index]
            if c.isNumber {
                text.append(c)
                seenDigit = true
                index += 1
            } else if c == "." && !seenDot {
                text.append(c)
                seenDot = true
                index += 1
            } else if (c == "e" || c == "E"), seenDigit,
                      index + 1 < chars.count,
                      chars[index + 1].isNumber || chars[index + 1] == "-" || chars[index + 1] == "+" {
                text.append(c)
                index += 1
                text.append(chars[index])
                index += 1
            } else {
                break
            }
        }
        guard seenDigit, let value = Double(text) else { return nil }
        return CGFloat(value)
    }
}

/// Official brand marks, as published by each project.
///
/// GitHub's is the Octocat from primer/octicons; Ko-fi's is the cup from their
/// press kit. Both are taken verbatim from simple-icons, which tracks the
/// upstream brand assets, so neither is a redrawing.
enum Brand {
    static let github = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
    static let kofi = "M11.351 2.715c-2.7 0-4.986.025-6.83.26C2.078 3.285 0 5.154 0 8.61c0 3.506.182 6.13 1.585 8.493 1.584 2.701 4.233 4.182 7.662 4.182h.83c4.209 0 6.494-2.234 7.637-4a9.5 9.5 0 0 0 1.091-2.338C21.792 14.688 24 12.22 24 9.208v-.415c0-3.247-2.13-5.507-5.792-5.87-1.558-.156-2.65-.208-6.857-.208m0 1.947c4.208 0 5.09.052 6.571.182 2.624.311 4.13 1.584 4.13 4v.39c0 2.156-1.792 3.844-3.87 3.844h-.935l-.156.649c-.208 1.013-.597 1.818-1.039 2.546-.909 1.428-2.545 3.064-5.922 3.064h-.805c-2.571 0-4.831-.883-6.078-3.195-1.09-2-1.298-4.155-1.298-7.506 0-2.181.857-3.402 3.012-3.714 1.533-.233 3.559-.26 6.39-.26m6.547 2.287c-.416 0-.65.234-.65.546v2.935c0 .311.234.545.65.545 1.324 0 2.051-.754 2.051-2s-.727-2.026-2.052-2.026m-10.39.182c-1.818 0-3.013 1.48-3.013 3.142 0 1.533.858 2.857 1.949 3.897.727.701 1.87 1.429 2.649 1.896a1.47 1.47 0 0 0 1.507 0c.78-.467 1.922-1.195 2.623-1.896 1.117-1.039 1.974-2.364 1.974-3.897 0-1.662-1.247-3.142-3.039-3.142-1.065 0-1.792.545-2.338 1.298-.493-.753-1.246-1.298-2.312-1.298"
}

/// A brand mark at a given size, tinted.
struct BrandMark: View {
    let path: String
    var size: CGFloat = 18

    var body: some View {
        SVGPath(commands: path)
            .frame(width: size, height: size)
    }
}

/// An outbound link, as a row that looks like the destination.
///
/// A `Link` in a `Form` renders as blue text, which reads as an afterthought
/// for the two places this app actually sends people. This gives each one its
/// own mark on its own colour, the row still behaves like a list row, and the
/// arrow says it leaves the app.
struct BrandLink: View {
    let path: String
    let title: String
    let subtitle: String
    let tint: Color
    var markColor: Color = .white
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openURL(url)
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint)
                    SVGPath(commands: path)
                        .fill(markColor)
                        .frame(width: 19, height: 19)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(Florin.text)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Florin.text3)
                        .monospaced()
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Florin.text3)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(.isLink)
    }
}
