import AVFoundation

/// Plays what the game's PLAY_SOUNDS played (`GameLoop.takeSounds`) as the
/// Apple's speaker would (`SpeakerRenderer`), one batch after the other.
/// The game waits while a sound plays, as on the Apple (the native routine
/// takes the sound's cycles), so a batch is played as soon as it is taken.
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(SpeakerRenderer.sampleRate), channels: 1)!
    /// The player node reaches the output; if not, nothing plays.
    private let connected: Bool

    init() {
        engine.attach(node)
        connected = (try? engine.connectNode(node, to: engine.mainMixerNode, format: format)) != nil
    }

    func play(_ sounds: [Sound.Played]) {
        let samples = SpeakerRenderer.samples(sounds)
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
    }
}
