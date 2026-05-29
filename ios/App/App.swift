import SwiftUI

@main
struct MacMirrorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden(true)
        }
    }
}
