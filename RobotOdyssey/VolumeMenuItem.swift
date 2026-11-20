import AppKit
import SwiftUI

/// The volume slider in Machine ▸ Sound, as Apple2Emu's. SwiftUI's menu bar
/// menus can't hold a slider, so the "Volume" item `GameCommands` puts there
/// gets a `VolumeSlider` as its AppKit view, each time a menu opens (SwiftUI
/// may have rebuilt the item since).
final class VolumeMenuItem {
    /// The title of the placeholder item that gets the slider.
    static let title = "Volume"

    private let view: NSView
    private var observer: NSObjectProtocol?

    init(model: ViewerModel) {
        let hosting = NSHostingView(rootView: VolumeSlider(model: model)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(width: 220))
        hosting.frame.size = hosting.fittingSize
        view = hosting
        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        }
    }

    private func install() {
        guard let item = NSApp.mainMenu?.item(withTitle: "Machine")?.submenu?
            .item(withTitle: "Sound")?.submenu?.item(withTitle: Self.title),
            item.view !== view
        else { return }
        item.view = view
    }
}

/// The game's volume (`ViewerModel.volume`), from silent to full, with
/// speaker icons at its ends; dimmed while the sound is off.
struct VolumeSlider: View {
    @Bindable var model: ViewerModel

    var body: some View {
        Slider(value: $model.volume, in: 0 ... 1) {
            Text("Volume")
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
        }
        .disabled(!model.sound)
    }
}
