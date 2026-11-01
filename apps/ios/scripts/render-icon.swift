#!/usr/bin/env swift
//
// L'icône, au trait.
//
// Même sujet qu'avant — le florin, sa pièce et son lys — mais dessiné au lieu
// d'être éclairé : un cercle, un filet à l'intérieur, et le lys en contour
// d'épaisseur constante. Aucun dégradé, aucune ombre, deux couleurs.
//
//   swift render-icon.swift <chemin de sortie>
//
import AppKit

let side = 1024.0
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon-1024.png")

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8,
    bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("contexte") }

// Repère SVG : y vers le bas.
ctx.translateBy(x: 0, y: side)
ctx.scaleBy(x: 1, y: -1)

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

let ink = CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
ctx.setStrokeColor(ink)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let c = 512.0

// Une seule épaisseur pour tout le dessin. Deux graisses, c'est déjà une
// hiérarchie, et il n'y a rien à hiérarchiser ici.
ctx.setLineWidth(32)

// La pièce.
ctx.strokeEllipse(in: CGRect(x: c - 384, y: c - 384, width: 768, height: 768))

// Le lys, un peu agrandi pour ne pas flotter dans la pièce. L'épaisseur est
// divisée d'autant : un trait doit rester le même trait partout.
ctx.saveGState()
ctx.translateBy(x: c, y: c)
ctx.scaleBy(x: 1.1, y: 1.1)
ctx.translateBy(x: -c, y: -c)
ctx.setLineWidth(32 / 1.1)

// Le lys : un contour, pas un bouquet de traits.
//
// La version d'avant empilait pétale, volute, queue et crosse — quatre traits
// par côté, chacun refermé sur lui-même. À soixante points ça ne faisait plus
// un lys, ça faisait des ailes. Ici une seule ligne part de la pointe, descend
// le pétale central, ressort en feuille latérale et revient se perdre sous le
// bandeau ; son miroir fait l'autre moitié, et les deux se rejoignent en
// pointe. Tout ce qui se termine mal se termine sous le bandeau.
let half = CGMutablePath()
half.move(to: CGPoint(x: c, y: 252))
half.addCurve(to: CGPoint(x: 586, y: 596),
              control1: CGPoint(x: 558, y: 352), control2: CGPoint(x: 596, y: 472))
half.addLine(to: CGPoint(x: 614, y: 596))
half.addCurve(to: CGPoint(x: 722, y: 522),
              control1: CGPoint(x: 648, y: 556), control2: CGPoint(x: 682, y: 522))
half.addCurve(to: CGPoint(x: 738, y: 612),
              control1: CGPoint(x: 752, y: 522), control2: CGPoint(x: 750, y: 568))
half.addCurve(to: CGPoint(x: 688, y: 708),
              control1: CGPoint(x: 730, y: 652), control2: CGPoint(x: 712, y: 682))
half.addCurve(to: CGPoint(x: 624, y: 606),
              control1: CGPoint(x: 670, y: 668), control2: CGPoint(x: 646, y: 634))

// Le pied : un V, et rien d'autre. Les deux queues qui s'écartent étaient le
// détail de trop.
let foot = CGMutablePath()
foot.move(to: CGPoint(x: 452, y: 630))
foot.addCurve(to: CGPoint(x: c, y: 752),
              control1: CGPoint(x: 466, y: 690), control2: CGPoint(x: 490, y: 730))
foot.addCurve(to: CGPoint(x: 572, y: 630),
              control1: CGPoint(x: 534, y: 730), control2: CGPoint(x: 558, y: 690))

let flip = CGAffineTransform(translationX: 2 * c, y: 0).scaledBy(x: -1, y: 1)
for p in [half, foot] {
    let both = CGMutablePath()
    both.addPath(p)
    both.addPath(p, transform: flip)
    ctx.addPath(both)
    ctx.strokePath()
}

// Le bandeau, qui tient le tout et cache les attaches.
let band = CGPath(
    roundedRect: CGRect(x: c - 132, y: 572, width: 264, height: 58),
    cornerWidth: 29, cornerHeight: 29, transform: nil
)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(band)
ctx.fillPath()
ctx.addPath(band)
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: out)
print("écrit \(out.path)")
