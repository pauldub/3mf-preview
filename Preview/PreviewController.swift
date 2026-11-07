import AppKit
import QuickLookUI

final class PreviewController: NSViewController, QLPreviewingController {
    override func loadView() { view = Viewer() }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let scene = try ModelLoader(url: url).load()
            loadViewIfNeeded()
            guard let viewer = view as? Viewer else { throw ModelError.invalid }
            try viewer.display(scene)
            handler(nil)
        } catch { handler(error) }
    }
}
