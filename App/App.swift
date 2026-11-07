import AppKit

@main
final class App: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "3MF Preview"
        let button = NSButton(title: "Open 3MF…", target: self, action: #selector(openFile))
        window.contentView = button
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["3mf"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        show(url)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let path = filenames.first { show(URL(fileURLWithPath: path)) }
    }
    private func show(_ url: URL) {
        do {
            let viewer = Viewer()
            try viewer.display(ModelLoader(url: url).load())
            window?.contentView = viewer
            window?.title = url.lastPathComponent
        } catch { NSAlert(error: error).runModal() }
    }
}
