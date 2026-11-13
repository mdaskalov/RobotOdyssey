import SwiftUI

/// The Apple TV app: the worlds to choose from, the game full screen
/// (`TVContentView`).  The engine and `ViewerModel` are the Mac app's; the
/// Mac's panels (the world, the current room, the toolbar) aren't here.
@main struct RobotOdysseyTV: App {
    var body: some Scene {
        WindowGroup {
            TVContentView()
        }
    }
}
