#if os(macOS)
import AppKit
import SwiftUI

/// View ▸ Zoom sizes the Mac's window: a zoom of 1…5 makes the canvas's
/// space (`ViewerModel.canvasSpace`) the room's size, the panels shown
/// keeping theirs; the window keeps its top left corner and stays on the
/// screen.  When the screen has no room for it the window fills the
/// screen and the zoom becomes Fit.  Resizing the window by hand makes
/// the zoom Fit too.
@MainActor
final class WindowSizer {
    private weak var window: NSWindow?
    private var observer: NSObjectProtocol?
    /// The window is being sized here: not a resize by hand.
    private var sizing = false

    /// The window the view is in, watched for resizing by hand.
    func attach(_ window: NSWindow, model: ViewerModel) {
        guard window !== self.window else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        self.window = window
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willStartLiveResizeNotification,
                                                          object: window, queue: .main) { [weak self, weak model] _ in
            MainActor.assumeIsolated {
                guard let self, !self.sizing, let model, model.zoom != 0 else { return }
                model.zoom = 0
            }
        }
    }

    /// The zoom chosen: the window sized for it, and again once laid out
    /// (a panel held to the window's size grows with it); then, if the room
    /// still has no room for it, the zoom becomes Fit.
    func choose(_ model: ViewerModel) {
        model.sizingWindow = true
        apply(model)
        DispatchQueue.main.async {
            self.apply(model)
            DispatchQueue.main.async {
                model.sizingWindow = false
                model.checkZoom()
            }
        }
    }

    /// The window sized for `model.zoom` (1…5); Fit leaves it as it is.
    private func apply(_ model: ViewerModel) {
        guard model.zoom > 0, let window else { return }
        let want = CGSize(width: 280 * CGFloat(model.zoom), height: 192 * CGFloat(model.zoom))
        let space = model.canvasSpace
        guard space.width > 0, space.height > 0 else { return }
        if window.styleMask.contains(.fullScreen) {
            // The window's size is the screen's: the zoom if the room fits.
            if want.width > space.width || want.height > space.height { model.zoom = 0 }
            return
        }
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        let size = CGSize(width: (frame.width + want.width - space.width).rounded(),
                          height: (frame.height + want.height - space.height).rounded())
        if size.width > visible.width || size.height > visible.height {
            setFrame(visible, of: window)
            model.zoom = 0
            return
        }
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - size.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - size.height)
        guard frame != window.frame else { return }
        setFrame(frame, of: window)
    }

    private func setFrame(_ frame: CGRect, of window: NSWindow) {
        sizing = true
        window.setFrame(frame, display: true, animate: true)
        sizing = false
    }
}

/// Hands the window the view is in to `found`.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Reader(found: found) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        let found: (NSWindow) -> Void

        init(found: @escaping (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}
#endif
