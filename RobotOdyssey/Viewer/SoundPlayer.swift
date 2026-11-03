import AVFoundation

/// Plays the speaker (`GameLoop.takeSpeaker`) as the Apple's would: its
/// clicks streamed to the cycle (`SpeakerStream`), the samples queued one
/// batch after the other as the machine runs.  The game waits while a sound
/// of the native PLAY_SOUNDS plays (the native takes the sound's cycles), so
/// its samples are all there at once.
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(SpeakerRenderer.sampleRate), channels: 1)!
    /// The player node reaches the output; if not, nothing plays.
    private let connected: Bool
    private var stream = SpeakerStream()

    init() {
        engine.attach(node)
        connected = (try? engine.connectNode(node, to: engine.mainMixerNode, format: format)) != nil
    }

    /// Takes the speaker's `clicks` up to cycle `now`; plays them unless
    /// `muted`.  `quiet`: nothing clicks for a while after `now`
    /// (`GameLoop.speakerQuiet`): the sound ends there, the cone settling.
    func play(_ clicks: [UInt64], upTo now: UInt64, quiet: Bool, muted: Bool) {
        let samples = stream.samples(clicks, upTo: now, quiet: quiet)
        if !muted { schedule(samples) }
    }

    /// Plays `samples` at once, in place of what is still to play.
    func play(_ samples: [Float]) {
        stop()
        schedule(samples)
    }

    /// Queues `samples` after what is still to play.
    private func schedule(_ samples: [Float]) {
        guard connected, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            if !engine.isRunning { try engine.start() }
            node.scheduleBuffer(buffer)
            if !node.isPlaying { try node.playAudio() }
        } catch {
            return
        }
    }

    /// Drops what is still to play.
    func stop() {
        node.stop()
        stream.reset()
    }
}
