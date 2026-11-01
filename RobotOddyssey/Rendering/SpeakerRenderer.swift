import Foundation

/// The Apple II's speaker as sound samples.  Each click ($C030) moves the
/// cone to its other side, so the sound is a square wave with an edge at
/// every click: here averaged over each sample, and with the DC taken out as
/// the speaker's coupling does (a high pass at about 35 Hz), which lets the
/// cone settle after the last click.  The clicks come from the native
/// PLAY_SOUNDS (`Sound.Played`), to the cycle as the original makes them.
enum SpeakerRenderer {
    static let sampleRate = 44_100
    /// Time for the cone to settle after the last click.
    static let settle = sampleRate / 50
    static let volume = 0.4

    /// Mono samples of `sounds`, each at its cycle from the first one's
    /// start, until the last one ends and the cone settles.
    static func samples(_ sounds: [Sound.Played]) -> [Float] {
        guard let origin = sounds.map(\.start).min(),
              let end = sounds.map({ $0.start + $0.cycles }).max() else { return [] }
        let clicks = sounds.flatMap { s in s.clicks.map { Double(s.start - origin) + Double($0) } }.sorted()
        let perSample = GameLoop.clock / Double(sampleRate)
        let count = Int((Double(end - origin) / perSample).rounded(.up)) + settle
        var side = -1.0, t = 0.0, next = 0
        var input = -1.0, output = 0.0
        let pole = 0.995
        return (0 ..< count).map { i in
            let sampleEnd = Double(i + 1) * perSample
            var sum = 0.0
            while next < clicks.count && clicks[next] < sampleEnd {
                sum += side * (clicks[next] - t)
                t = clicks[next]
                side = -side
                next += 1
            }
            sum += side * (sampleEnd - t)
            t = sampleEnd
            let x = sum / perSample
            output = x - input + pole * output
            input = x
            return Float(max(-1, min(1, output * volume)))
        }
    }
}
