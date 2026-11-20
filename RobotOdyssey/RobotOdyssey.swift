import AppKit
import SwiftUI

/// The Mac app: one window (`ContentView`), the menus (`GameCommands`).
/// It starts playing, without the panels.
@main struct RobotOdyssey: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Robot Odyssey", id: "main") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 1180, height: 900)
        .commands { GameCommands(model: delegate.model) }
    }
}

/// Holds the model, for the window and the menus (the volume slider's too).
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ViewerModel()
    private var volumeItem: VolumeMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        volumeItem = VolumeMenuItem(model: model)
    }

    /// The app has a single window; closing it quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
