#if os(macOS)
import AppKit

/// The Mac's mouse taken by the canvas (`ViewerModel.takeMouse`): the pointer
/// hidden and held where it is, its motion and its button go to `onMove`
/// and `onButton` instead of the views.  A press of ⌘ alone (down and up,
/// no key, click or other modifier in between) calls `onCommand`, taken or
/// not.  An event monitor of the app's own events, from `start` to `stop`.
final class MouseCapture {
    /// The pointer moved by (dx, dy) points, y down.
    var onMove: ((CGFloat, CGFloat) -> Void)?
    /// The (left) button went down or up.
    var onButton: ((Bool) -> Void)?
    /// ⌘ pressed and let go alone, in the active app.
    var onCommand: (() -> Void)?
    private(set) var isTaken = false
    private var monitor: Any?
    /// The window the mouse was taken in, and whether it took mouse-moved events before.
    private var window: (window: NSWindow, acceptedMoves: Bool)?
    /// ⌘ is down, with nothing else since it went down.
    private var commandAlone = false
    /// The modifiers down at the last change.
    private var lastFlags: NSEvent.ModifierFlags = []

    /// The modifiers that make ⌘ not alone (Caps Lock and the like don't).
    private static let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    func start() {
        guard monitor == nil else { return }
        let types: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .mouseMoved, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        monitor = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        give()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Takes the mouse: the pointer hidden and held still, its motion read.
    func take() {
        guard !isTaken else { return }
        isTaken = true
        if let key = NSApp.keyWindow {
            window = (key, key.acceptsMouseMovedEvents)
            key.acceptsMouseMovedEvents = true      // the motion comes as mouse-moved events
        }
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    /// Gives the mouse back: the pointer shown again, at `point` (the
    /// window's coordinates as SwiftUI's global space has them, from the top
    /// left) if there is one, else where it was held.
    func give(at point: CGPoint? = nil) {
        guard isTaken else { return }
        isTaken = false
        commandAlone = false
        if let point, let screen = window.flatMap({ screenPoint(point, in: $0.window) }) {
            CGWarpMouseCursorPosition(screen)
        }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        if let window { window.window.acceptsMouseMovedEvents = window.acceptedMoves }
        window = nil
    }

    /// Where `point` of `window`'s content (SwiftUI's global space) is on
    /// the display, as CGWarpMouseCursorPosition takes it (from the top left
    /// of the main display).
    private func screenPoint(_ point: CGPoint, in window: NSWindow) -> CGPoint? {
        guard let content = window.contentView, let main = NSScreen.screens.first else { return nil }
        let inView = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
        let onScreen = window.convertPoint(toScreen: content.convert(inView, to: nil))
        return CGPoint(x: onScreen.x, y: main.frame.maxY - onScreen.y)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(MouseCapture.modifiers)
            if flags == .command && lastFlags.isEmpty {
                commandAlone = true
            } else {
                if flags.isEmpty && lastFlags == .command && commandAlone && NSApp.isActive { onCommand?() }
                commandAlone = false
            }
            lastFlags = flags
        case .keyDown, .scrollWheel:
            commandAlone = false
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            guard isTaken else { break }
            onMove?(event.deltaX, event.deltaY)
            return nil
        case .leftMouseDown, .leftMouseUp:
            commandAlone = false
            guard isTaken else { break }
            onButton?(event.type == .leftMouseDown)
            return nil
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            commandAlone = false
            if isTaken { return nil }
        default:
            break
        }
        return event
    }
}
#else
import CoreGraphics

/// No mouse to take where there is no pointer (tvOS): the same calls, none
/// of them doing anything.
final class MouseCapture {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onButton: ((Bool) -> Void)?
    var onCommand: (() -> Void)?
    private(set) var isTaken = false

    func start() {}
    func stop() {}
    func take() {}
    func give(at point: CGPoint? = nil) {}
}
#endif
