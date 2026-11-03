import QuartzCore
#if os(macOS)
import AppKit
#endif

/// The display's frames, up to 60 a second (CADisplayLink): the time each
/// will be on screen (CACurrentMediaTime's clock), as they come.  The game
/// runs and shows frame by frame (`ViewerModel.runGame`), in step with the
/// screen.  Without a display, a timer stands in.
enum DisplayFrames {
    static func stream() -> AsyncStream<CFTimeInterval> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let target = Target { continuation.yield($0) }
            #if os(macOS)
            let link = NSScreen.main?.displayLink(target: target, selector: #selector(Target.frame))
            #else
            let link: CADisplayLink? = CADisplayLink(target: target, selector: #selector(Target.frame))
            #endif
            guard let link else {
                let timer = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(16))
                        continuation.yield(CACurrentMediaTime())
                    }
                }
                continuation.onTermination = { _ in timer.cancel() }
                return
            }
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            continuation.onTermination = { _ in
                Task { @MainActor in link.invalidate() }
            }
        }
    }

    private final class Target: NSObject {
        let onFrame: (CFTimeInterval) -> Void

        init(_ onFrame: @escaping (CFTimeInterval) -> Void) {
            self.onFrame = onFrame
        }

        @objc func frame(_ link: CADisplayLink) {
            onFrame(link.targetTimestamp)
        }
    }
}
