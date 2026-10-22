import SwiftUI

@main
struct FileBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 500)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}
