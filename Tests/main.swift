import AppKit
import SceneKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["tetrahedron", "assembly"] {
    let scene = try ModelLoader(url: root.appendingPathComponent(name + ".3mf")).load()
    let bounds = scene.rootNode.boundingBox
    let expected: Float = name == "assembly" ? 40 : 0
    precondition(abs(Float(bounds.min.x) - expected) < 0.001)
    precondition(abs(Float(bounds.max.x) - expected - 20) < 0.001)
    let viewer = Viewer()
    try viewer.display(scene)
    if name == "tetrahedron", let image = viewer.snapshot().tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: image),
       let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: root.deletingLastPathComponent().appendingPathComponent("preview.png"))
    }
    print("PASS \(name)")
}
for name in ["cycle", "bad-index", "empty", "corrupt"] {
    do {
        _ = try ModelLoader(url: root.appendingPathComponent(name + ".3mf")).load()
        fatalError("Accepted invalid fixture: \(name)")
    } catch { print("PASS rejects \(name)") }
}

let plated = try ModelLoader(url: root.appendingPathComponent("plates.3mf")).load()
let beds = plated.rootNode.childNodes.filter { $0.name?.hasPrefix("plate-") == true }
precondition(beds.count == 4)
precondition(beds[1].position.x == 240)
precondition(beds[2].position.y == -180)
precondition(beds[3].position.x == 240 && beds[3].position.y == -180)
for bed in beds {
    precondition(bed.childNodes.first?.boundingBox.max.z ?? 1 > 0)
    let body = bed.childNodes[0]
    precondition(body.boundingBox.max.z + body.position.z < 0)
}
let viewer = Viewer()
try viewer.display(plated)
if let data = viewer.snapshot().tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: data),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: root.deletingLastPathComponent().appendingPathComponent("plates.png"))
}
print("PASS four plates, positions, and surface below models")
let badBed = try ModelLoader(url: root.appendingPathComponent("bad-bed.3mf")).load()
precondition(badBed.rootNode.childNodes.count == 1)
print("PASS invalid bed preserves model")

if CommandLine.arguments.count > 2 {
    let real = try ModelLoader(url: URL(fileURLWithPath: CommandLine.arguments[2])).load()
    precondition(real.rootNode.childNodes.contains { $0.name == "plate-1" })
    print("PASS real project plate")
}
