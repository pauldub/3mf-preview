import AppKit
import SceneKit

// Share the same camera and renderer between the host and Quick Look.
final class Viewer: SCNView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), options: nil)
        allowsCameraControl = true
        autoenablesDefaultLighting = true
        backgroundColor = .windowBackgroundColor
        antialiasingMode = .multisampling4X
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func display(_ scene: SCNScene) throws {
        let bounds = scene.rootNode.boundingBox
        let center = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                (bounds.min.y + bounds.max.y) / 2,
                                (bounds.min.z + bounds.max.z) / 2)
        let span = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y,
                       bounds.max.z - bounds.min.z)
        guard span.isFinite, span > 0 else { throw ModelError.invalid }
        // Normalize units and rotate the printer's Z-up coordinates into SceneKit Y-up.
        let content = SCNNode()
        for child in scene.rootNode.childNodes { content.addChildNode(child) }
        content.position = SCNVector3(-center.x / span, -center.z / span, center.y / span)
        content.scale = SCNVector3(1 / span, 1 / span, 1 / span)
        content.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(content)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 100
        camera.position = SCNVector3(1.4, 1.1, 1.8)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        self.scene = scene
        pointOfView = camera
        defaultCameraController.target = SCNVector3Zero
    }
}
