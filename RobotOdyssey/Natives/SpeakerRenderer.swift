import Apple2Kit
import Foundation

/// The speaker (Apple2Kit's `SpeakerRenderer`) playing what the native
/// PLAY_SOUNDS (`Sound.Played`) reports, to the cycle as the original makes
/// its clicks.  The 6502 code's clicks stream (`GameLoop.takeSpeaker`,
/// `SpeakerStream`).
nonisolated extension SpeakerRenderer {
    /// Mono samples of `sounds`, each at its cycle from the first one's
    /// start, until the last one ends and the cone settles.
    static func samples(_ sounds: [Sound.Played]) -> [Float] {
        guard let origin = sounds.map(\.start).min(),
              let end = sounds.map({ $0.start + $0.cycles }).max() else { return [] }
        let clicks = sounds.flatMap { s in s.clicks.map { Double(s.start - origin) + Double($0) } }.sorted()
        let count = Int((Double(end - origin) / perSample).rounded(.up)) + settle
        var speaker = SpeakerRenderer()
        return speaker.samples(count, clicks: clicks)
    }
}
