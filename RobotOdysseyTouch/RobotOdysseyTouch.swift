import SwiftUI

/// The iPhone and iPad app: the game full screen from launch, the menu
/// over it (`TouchContentView`), as on the Apple TV.  The engine and
/// `ViewerModel` are the Mac app's; the Mac's panels aren't here.
@main struct RobotOdysseyTouch: App {
    var body: some Scene {
        WindowGroup {
            TouchContentView()
        }
    }
}
