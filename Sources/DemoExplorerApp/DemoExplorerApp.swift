import AppKit
import DemoExplorer

@main
enum DemoExplorerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Explicit because bare `swift run` binaries would otherwise surface
        // as background processes; .regular gives the proper app experience.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
