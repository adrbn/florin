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
// La planche est déclarée ×3, et une image y fait exactement trois fois le
// côté affiché par SplashView : un pixel rendu pour un pixel d'écran. Déclarée
// ×1, iOS la rééchantillonne à l'affichage et la gravure devient molle.
//
import AppKit
import SceneKit

let cell = 222            // côté d'une image, en pixels (74 pt à l'écran, ×3)
let columns = 6, rows = 5 // 30 images pour un tour : 12° entre deux
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
        NSColor(calibratedWhite: 0.80, alpha: 1),
        NSColor(calibratedWhite: 0.46, alpha: 1),
        NSColor(calibratedWhite: 0.14, alpha: 1),
    ])?.draw(in: rect, angle: -90)
    return true
}
scene.lightingEnvironment.contents = sky
scene.lightingEnvironment.intensity = 0.85

let coin = SCNCylinder(radius: 1, height: 0.17)
coin.radialSegmentCount = 96

let gold = SCNMaterial()
gold.lightingModel = .physicallyBased
gold.diffuse.contents = NSColor(srgbRed: 0.87, green: 0.70, blue: 0.34, alpha: 1)
gold.metalness.contents = 1.0
// Un or bien poli ne renvoie qu'un trait de lumière, et ce trait traverse la
// tranche d'un coup au milieu du tour : c'est exactement l'éclat qu'il ne
// veut pas voir. Mat, la tranche se contente de tourner.
gold.roughness.contents = 0.46

/*
 * La face n'est pas éclairée, et c'est volontaire.
 *
 * Le dessin porte déjà sa lumière : son relief, son listel, le satiné du
 * métal y sont peints. Le repasser sous un éclairage physique l'éclaire deux
 * fois — l'or vire au brun sous l'ombre ajoutée, la gravure se noie. C'est ce
 * que donnait la première version, et c'est ce qu'il a appelé moche.
 *
 * Rendue telle quelle, la face est exactement celle que l'app affiche
 * ailleurs ; la 3D ne sert qu'à ce que le dessin seul ne peut pas faire : une
 * tranche, une perspective, une silhouette qui se referme.
 */
let cap = SCNMaterial()
cap.lightingModel = .constant
cap.diffuse.contents = face
// Le cylindre pose la texture d'une face à l'endroit et l'autre en miroir :
// c'est exactement ce qu'on veut, le dos d'une pièce est le reflet de sa face.

// L'ordre de SCNCylinder : flanc, dessus, dessous.
coin.materials = [gold, cap, cap]

let node = SCNNode(geometry: coin)
// Couchée : l'axe du cylindre devient horizontal, la pièce nous fait face.
node.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)

/*
 * La gravure d'aplomb.
 *
 * Coucher le cylindre amène aussi sa texture sur le flanc : le lys sortait
 * du rendu couché, pointe à droite. On fait donc tourner la pièce d'un quart
 * de tour sur son propre axe — comme on la tournerait entre deux doigts — et
 * non sa texture : les deux faces tournent alors ensemble, alors qu'une
 * image tournée aurait laissé le dos, qui est son miroir, la pointe en bas.
 */
let upright = SCNNode()
upright.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
upright.addChildNode(node)

let spinner = SCNNode()
spinner.addChildNode(upright)
scene.rootNode.addChildNode(spinner)

let camera = SCNCamera()
camera.usesOrthographicProjection = false
camera.fieldOfView = 23
// Ni HDR ni bloom : c'est le halo qu'ils fabriquent autour de la pièce qu'on
// ne veut pas. Un or qui brille est un or peint, pas un or allumé.
camera.wantsHDR = false
let cameraNode = SCNNode()
cameraNode.camera = camera
// Un peu au-dessus : quelques degrés suffisent à faire un disque posé dans une
// pièce plutôt qu'un cercle sur une page.
// Assez loin pour que la pièce ne touche jamais le bord de son image : une
// ellipse de profil est plus haute que large, et la plus large des vues doit
// garder sa marge, sinon un côté se coupe net au milieu du tour.
cameraNode.position = SCNVector3(0, 0.55, 5.6)
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
// Deux lumières douces, et rien de frontal : la face s'éclaire toute seule,
// seule la tranche a besoin d'être vue.
scene.rootNode.addChildNode(light(.directional, intensity: 420, at: SCNVector3(-2.5, 3, 4)))
scene.rootNode.addChildNode(light(.directional, intensity: 240, at: SCNVector3(3, -1, 2)))

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
    { "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "filename" : "coinspin.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

/*
 * Une planche de métal sur fond transparent pèse quatre mégaoctets en PNG
 * vrai, pour une app qui en pèse cinq. Elle n'a pourtant que des ors : une
 * palette de 256 couleurs la rend à l'œil nu identique et dix fois plus
 * légère. Si l'outil n'est pas là, l'image reste juste — et lourde.
 */
let sheetURL = outDir.appendingPathComponent("coinspin.png")
for tool in ["/opt/homebrew/bin/pngquant", "/usr/local/bin/pngquant"]
where FileManager.default.isExecutableFile(atPath: tool) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: tool)
    task.arguments = ["--force", "--skip-if-larger", "--quality", "65-92",
                      "--output", sheetURL.path, "256", sheetURL.path]
    try task.run()
    task.waitUntilExit()
    break
}

let weight = (try? FileManager.default.attributesOfItem(atPath: sheetURL.path)[.size]) ?? 0
print("\(frames) images, \(cell)px, \(weight) octets — \(sheetURL.path)")
