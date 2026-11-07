import Foundation
import SceneKit

private struct Reference {
    let id: String
    let path: String?
    let transform: SCNMatrix4
}

private struct Mesh {
    var vertices: [SCNVector3] = []
    var indices: [Int32] = []
    var components: [Reference] = []
}

// Parse mesh resources separately from build instances to preserve assemblies.
private final class Model: NSObject, XMLParserDelegate {
    private(set) var objects: [String: Mesh] = [:]
    private(set) var build: [Reference] = []
    private var current: String?
    private var failure: Error?
    private static let triangleLimit = 3_000_000

    init(data: Data) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), failure == nil else { throw failure ?? ModelError.invalid }
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        do {
            switch name {
            case "object":
                guard let id = a["id"], objects[id] == nil else { throw ModelError.invalid }
                current = id
                objects[id] = Mesh()
            case "vertex":
                guard let id = current, let x = Float(a["x"] ?? ""),
                      let y = Float(a["y"] ?? ""), let z = Float(a["z"] ?? ""),
                      x.isFinite, y.isFinite, z.isFinite else { throw ModelError.invalid }
                objects[id]?.vertices.append(SCNVector3(x, y, z))
            case "triangle":
                // Keep only counts: retaining a mesh value copies its array on append.
                guard let id = current, let vertexCount = objects[id]?.vertices.count,
                      let indexCount = objects[id]?.indices.count,
                      indexCount / 3 < Self.triangleLimit else { throw ModelError.limit }
                for key in ["v1", "v2", "v3"] {
                    guard let index = Int32(a[key] ?? ""), index >= 0,
                          index < vertexCount else { throw ModelError.invalid }
                    objects[id]?.indices.append(index)
                }
            case "component", "item":
                guard let id = a["objectid"] else { throw ModelError.invalid }
                let ref = Reference(id: id, path: a.first { $0.key.hasSuffix(":path") }?.value,
                                    transform: try matrix(a["transform"]))
                if name == "item" { build.append(ref) }
                else if let current { objects[current]?.components.append(ref) }
            default: break
            }
        } catch {
            failure = error
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        if name == "object" { current = nil }
    }

    private func matrix(_ value: String?) throws -> SCNMatrix4 {
        guard let value else { return SCNMatrix4Identity }
        let values = value.split(whereSeparator: \.isWhitespace).compactMap { Double($0).map { CGFloat($0) } }
        guard values.count == 12, values.allSatisfy({ $0.isFinite }) else { throw ModelError.invalid }
        return SCNMatrix4(m11: values[0], m12: values[1], m13: values[2], m14: 0,
                          m21: values[3], m22: values[4], m23: values[5], m24: 0,
                          m31: values[6], m32: values[7], m33: values[8], m34: 0,
                          m41: values[9], m42: values[10], m43: values[11], m44: 1)
    }
}

final class ModelLoader {
    private let package: Package
    private var models: [String: Model] = [:]
    private var instances = 0
    private static let instanceLimit = 20_000
    private static let depthLimit = 64

    init(url: URL) throws { package = try Package(url: url) }

    func load() throws -> SCNScene {
        let path = try package.root()
        let model = try model(path)
        guard !model.build.isEmpty else { throw ModelError.invalid }
        let scene = SCNScene()
        for ref in model.build {
            scene.rootNode.addChildNode(try node(ref, path: path, ancestors: []))
        }
        if let settings = try? package.data(Plates.settingsPath),
           let plates = Plates(settings: settings, layout: try? package.data(Plates.layoutPath)) {
            for plate in plates.nodes() { scene.rootNode.addChildNode(plate) }
        }
        return scene
    }

    private func model(_ path: String) throws -> Model {
        if let model = models[path] { return model }
        let model = try Model(data: package.data(path))
        models[path] = model
        return model
    }

    private func node(_ ref: Reference, path: String, ancestors: Set<String>) throws -> SCNNode {
        instances += 1
        guard instances <= Self.instanceLimit, ancestors.count < Self.depthLimit else { throw ModelError.limit }
        let target = try ref.path.map { try package.resolve($0, from: path) } ?? path
        let key = target + "#" + ref.id
        guard !ancestors.contains(key), let mesh = try model(target).objects[ref.id] else {
            throw ModelError.invalid
        }
        let node = SCNNode()
        node.transform = ref.transform
        if !mesh.indices.isEmpty {
            let source = SCNGeometrySource(vertices: mesh.vertices)
            let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = NSColor.systemTeal
            material.isDoubleSided = true
            material.lightingModel = .blinn
            geometry.materials = [material]
            node.geometry = geometry
        }
        for child in mesh.components {
            node.addChildNode(try self.node(child, path: target, ancestors: ancestors.union([key])))
        }
        return node
    }
}
