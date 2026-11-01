import SwiftUI

@main struct RobotOdyssey: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 950)
        #endif
    }
}
