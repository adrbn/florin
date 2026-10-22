#!/usr/bin/env swift
//
// Fabrique la planche d'images du lancement : une vraie pièce en or qui tourne.
//
// Dessiner une pièce épaisse en SwiftUI demande de simuler ce qu'un moteur 3D
// fait pour rien — la tranche, son ombre propre, le reflet qui glisse sur le
// métal, la silhouette quand elle est de profil. Chaque approximation se voyait
// quelque part : un halo, un cran sur le bord, un reflet qui ne suit pas.
//
// Ici la pièce est un cylindre, l'or est un matériau, la lumière est une
// lumière. Le rendu se fait une fois, sur le Mac, et l'app ne joue plus que des
// images — aucun calcul au lancement, aucune dépendance, et le résultat ne peut
// plus « casser » puisqu'il n'y a plus rien à recalculer.
//
//   swift scripts/render-coin.swift
//
// Écrit Florin/Assets.xcassets/CoinSpin.imageset/coinspin.png : une grille de
// COLUMNS × ROWS images couvrant un tour complet, dans l'ordre de lecture.
//
import AppKit
import SceneKit

let cell = 176            // côté d'une image, en pixels (62 pt à l'écran, ×3)
let columns = 6, rows = 4 // 24 images pour un tour : 15° entre deux
let frames = columns * rows

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? ".")
let faceURL = root.appendingPathComponent("Florin/Assets.xcassets/CoinFace.imageset/coin.png")
let outDir = root.appendingPathComponent("Florin/Assets.xcassets/CoinSpin.imageset")

guard let face = NSImage(contentsOf: faceURL) else {
    fatalError("coin.png introuvable à \(faceURL.path)")
}

// MARK: - La scène

let scene = SCNScene()

/*
 * Un métal ne se voit que par ce qu'il reflète : sans environnement, une
 * surface métallique en rendu physique est noire. Le dégradé ci-dessous tient
 * lieu de ciel — clair en haut, sombre en bas — et c'est lui qu'on voit
 * glisser sur la tranche pendant la rotation.
 */
let sky = NSImage(size: NSSize(width: 64, height: 256), flipped: false) { rect in
    NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 1),
        NSColor(calibratedWhite: 0.55, alpha: 1),
        NSColor(calibratedWhite: 0.12, alpha: 1),
    ])?.draw(in: rect, angle: -90)
    return true
}
scene.lightingEnvironment.contents = sky
scene.lightingEnvironment.intensity = 1.0

let coin = SCNCylinder(radius: 1, height: 0.17)
coin.radialSegmentCount = 96

let gold = SCNMaterial()
gold.lightingModel = .physicallyBased
gold.diffuse.contents = NSColor(srgbRed: 0.93, green: 0.76, blue: 0.36, alpha: 1)
gold.metalness.contents = 1.0
gold.roughness.contents = 0.22

let cap = SCNMaterial()
cap.lightingModel = .physicallyBased
cap.diffuse.contents = face
cap.metalness.contents = 0.55
cap.roughness.contents = 0.42
// Le cylindre pose la texture d'une face à l'endroit et l'autre en miroir :
// c'est exactement ce qu'on veut, le dos d'une pièce est le reflet de sa face.

// L'ordre de SCNCylinder : flanc, dessus, dessous.
coin.materials = [gold, cap, cap]

let node = SCNNode(geometry: coin)
// Couchée : l'axe du cylindre devient horizontal, la pièce nous fait face.
node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
let spinner = SCNNode()
spinner.addChildNode(node)
scene.rootNode.addChildNode(spinner)

let camera = SCNCamera()
camera.usesOrthographicProjection = false
camera.fieldOfView = 23
camera.wantsHDR = true
camera.bloomIntensity = 0.06
camera.bloomThreshold = 0.95
let cameraNode = SCNNode()
cameraNode.camera = camera
// Un peu au-dessus : quelques degrés suffisent à faire un disque posé dans une
// pièce plutôt qu'un cercle sur une page.
cameraNode.position = SCNVector3(0, 0.55, 5.05)
cameraNode.eulerAngles = SCNVector3(-0.108, 0, 0)
scene.rootNode.addChildNode(cameraNode)

func light(_ kind: SCNLight.LightType, intensity: CGFloat, at p: SCNVector3) -> SCNNode {
    let l = SCNLight()
    l.type = kind
    l.intensity = intensity
    l.castsShadow = false
    let n = SCNNode()
    n.light = l
    n.position = p
    n.look(at: SCNVector3(0, 0, 0))
    return n
}
scene.rootNode.addChildNode(light(.directional, intensity: 700, at: SCNVector3(-2.5, 3, 4)))
scene.rootNode.addChildNode(light(.directional, intensity: 420, at: SCNVector3(3, -1, 2)))
scene.rootNode.addChildNode(light(.omni, intensity: 140, at: SCNVector3(0, 0, 6)))

// MARK: - Le rendu

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("pas de Metal") }
let renderer = SCNRenderer(device: device, options: nil)
renderer.scene = scene
renderer.pointOfView = cameraNode
renderer.autoenablesDefaultLighting = false

let sheet = NSImage(size: NSSize(width: cell * columns, height: cell * rows))
sheet.lockFocus()
NSColor.clear.set()
NSBezierPath.fill(NSRect(origin: .zero, size: sheet.size))
for frame in 0..<frames {
    spinner.eulerAngles = SCNVector3(0, CGFloat(frame) / CGFloat(frames) * 2 * .pi, 0)
    let shot = renderer.snapshot(
        atTime: 0,
        with: CGSize(width: cell, height: cell),
        antialiasingMode: .multisampling4X
    )
    // Coordonnées AppKit : la première image en haut à gauche.
    let x = frame % columns, y = rows - 1 - frame / columns
    shot.draw(in: NSRect(x: x * cell, y: y * cell, width: cell, height: cell))
}
sheet.unlockFocus()

guard let tiff = sheet.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("encodage PNG impossible") }

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try png.write(to: outDir.appendingPathComponent("coinspin.png"))
try """
{
  "images" : [
    { "filename" : "coinspin.png", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("\(frames) images, \(cell)px — \(outDir.path)/coinspin.png")
