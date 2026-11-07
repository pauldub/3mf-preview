import AppKit
import SceneKit

// Read slicer bed metadata without making it a requirement for ordinary 3MFs.
final class Plates {
    static let settingsPath = "Metadata/project_settings.config"
    static let layoutPath = "Metadata/model_settings.config"
    private static let plateLimit = 256
    private static let pointLimit = 1024
    private static let slicerGap: CGFloat = 0.2
    private static let gridDivisions: CGFloat = 10
    private static let thicknessRatio: CGFloat = 0.004
    private static let textRatio: CGFloat = 0.035
    private let polygon: [CGPoint]
    private let names: [String]
    private let bounds: CGRect

    init?(settings: Data, layout: Data?) {
        guard let json = try? JSONSerialization.jsonObject(with: settings) as? [String: Any],
              let area = json["printable_area"] as? [String],
              area.count >= 3, area.count <= Self.pointLimit else { return nil }
        let points = area.compactMap { value -> CGPoint? in
            let pair = value.split(separator: "x").compactMap { Double($0) }
            guard pair.count == 2, pair.allSatisfy({ $0.isFinite && abs($0) < 1_000_000 }) else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        guard points.count == area.count,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              maxX > minX, maxY > minY else { return nil }
        polygon = points
        bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let layout {
            let reader = PlateNames()
            guard reader.read(layout), !reader.names.isEmpty,
                  reader.names.count <= Self.plateLimit else { return nil }
            names = reader.names
        } else { names = [""] }
    }

    func nodes() -> [SCNNode] {
        let columns = Int(ceil(sqrt(Double(names.count))))
        return names.enumerated().map { index, name in
            let node = bed()
            node.name = "plate-\(index + 1)"
            node.position = SCNVector3(CGFloat(index % columns) * bounds.width * (1 + Self.slicerGap),
                                      -CGFloat(index / columns) * bounds.height * (1 + Self.slicerGap), 0)
            let title = name.isEmpty ? "Plate \(index + 1)" : "Plate \(index + 1) · \(name)"
            node.addChildNode(label(title))
            return node
        }
    }

    private func bed() -> SCNNode {
        let path = NSBezierPath()
        path.move(to: polygon[0])
        for point in polygon.dropFirst() { path.line(to: point) }
        path.close()
        let thickness = min(bounds.width, bounds.height) * Self.thicknessRatio
        let shape = SCNShape(path: path, extrusionDepth: thickness)
        shape.firstMaterial = material(NSColor(white: 0.19, alpha: 1))
        let node = SCNNode()
        let body = SCNNode(geometry: shape)
        body.position.z = -shape.boundingBox.max.z - thickness / 10
        node.addChildNode(body)
        // Put the surface below Z=0 so first-layer triangles remain visible.
        let surface = SCNNode()
        surface.position.z = -thickness / 20
        surface.addChildNode(lines(polygon + [polygon[0]], color: .lightGray))
        let step = max(bounds.width, bounds.height) / Self.gridDivisions
        for x in stride(from: bounds.minX + step, to: bounds.maxX, by: step) {
            surface.addChildNode(grid(at: x, axis: .vertical))
        }
        for y in stride(from: bounds.minY + step, to: bounds.maxY, by: step) {
            surface.addChildNode(grid(at: y, axis: .horizontal))
        }
        node.addChildNode(surface)
        return node
    }

    private enum Axis { case horizontal, vertical }

    private func grid(at value: CGFloat, axis: Axis) -> SCNNode {
        // Clip each grid line to the actual polygon, including round beds.
        let points = axis == .vertical ? polygon : polygon.map { CGPoint(x: $0.y, y: $0.x) }
        var hits: [CGFloat] = []
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            guard (a.x <= value && b.x > value) || (b.x <= value && a.x > value) else { continue }
            hits.append(a.y + (value - a.x) * (b.y - a.y) / (b.x - a.x))
        }
        hits.sort()
        let node = SCNNode()
        for index in stride(from: 0, to: hits.count - hits.count % 2, by: 2) {
            let ends = [hits[index], hits[index + 1]].map {
                axis == .vertical ? CGPoint(x: value, y: $0) : CGPoint(x: $0, y: value)
            }
            node.addChildNode(lines(ends, color: NSColor(white: 0.30, alpha: 1)))
        }
        return node
    }

    private func lines(_ points: [CGPoint], color: NSColor) -> SCNNode {
        let vertices = points.map { SCNVector3($0.x, $0.y, 0) }
        var indices: [Int32] = []
        for index in 0..<(points.count - 1) { indices += [Int32(index), Int32(index + 1)] }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        return node
    }

    private func label(_ title: String) -> SCNNode {
        let size = min(bounds.width, bounds.height) * Self.textRatio
        let text = SCNText(string: String(title.prefix(80)), extrusionDepth: 0)
        text.font = .systemFont(ofSize: size, weight: .medium)
        text.flatness = 0.2
        text.firstMaterial = material(.lightGray)
        let node = SCNNode(geometry: text)
        node.position = SCNVector3(bounds.minX, bounds.minY - size * 2, 0)
        return node
    }

    private func material(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        return material
    }
}

private final class PlateNames: NSObject, XMLParserDelegate {
    private(set) var names: [String] = []
    private var inPlate = false
    private var inInstance = false
    private var name = ""

    func read(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if element == "plate" { inPlate = true; name = "" }
        if element == "model_instance" { inInstance = true }
        if inPlate && !inInstance && element == "metadata" && a["key"] == "plater_name" {
            name = a["value"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if element == "model_instance" { inInstance = false }
        if element == "plate" { names.append(name); inPlate = false }
    }
}
