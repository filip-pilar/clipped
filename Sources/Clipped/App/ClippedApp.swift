import SwiftUI

@main
struct ClippedApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_020, height: 860)
    }
}
