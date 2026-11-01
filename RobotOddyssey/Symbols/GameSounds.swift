import Foundation

/// A sound of the game, as PLAY_SOUNDS ($9F3C) plays a queued sound: a tone
/// or noise given by its length, sweep and pitch (Docs/Sound.md).  The worlds
/// queue them by number from their sound tables (WORLD_SOUND), a few from
/// their own code with a computed pitch: such a sound has a pitch for each
/// value.  What the speaker plays is not taken from here: the native
/// PLAY_SOUNDS reports every click, as the original makes them
/// (`SpeakerRenderer`).  The map names what was played.
struct Sound {
    /// The queue's flags, bits 7 and 6.
    enum Kind: UInt8 {
        /// A square wave: a click every period.
        case tone = 0x00
        /// A click after every period at the next 1 of a shift register.
        case noise = 0x80
        /// Noise whose falling period goes on through 0 (PLAY_SOUNDS patches
        /// PLAY_NOISE for it); no world uses it.
        case noiseWrapping = 0xC0

        init(flags: UInt8) {
            self = flags & 0x80 == 0 ? .tone : (flags & 0x40 == 0 ? .noise : .noiseWrapping)
        }
    }

    /// What PLAY_SOUNDS takes from a queue slot, but the room.
    struct Parameters: Hashable, CustomStringConvertible {
        let kind: Kind
        let length: UInt8
        let sweep: UInt8
        let pitch: UInt8

        var description: String { String(format: "%@ length $%02X sweep $%02X pitch $%02X", "\(kind)", length, sweep, pitch) }
    }

    let kind: Kind
    let length: UInt8
    let sweep: UInt8
    let pitches: [UInt8]
    /// The name is a guess.
    let guess: Bool

    init(_ kind: Kind, length: UInt8, sweep: UInt8, pitch: UInt8..., guess: Bool = false) {
        self.kind = kind
        self.length = length
        self.sweep = sweep
        pitches = pitch
        self.guess = guess
    }

    /// A sound PLAY_SOUNDS played: its name (nil: not in the map), the CPU
    /// cycle it started at (PLAY_TONE's or PLAY_NOISE's entry), the cycles it
    /// took up to its RTS, and its clicks by cycle from the start.
    struct Played {
        let parameters: Parameters
        let name: String?
        let start: UInt64
        let cycles: UInt64
        let clicks: [UInt32]
    }
}

/// The game's sounds by name, as GameSymbols names memory: every sound the
/// worlds play, with the numbers they have in the worlds' sound tables.  With
/// several pitches, each has the name with its pitch (`exitTones_28`).
/// Data/ro_sounds.sh checks the worlds' tables against the map.
final class GameSounds: Sendable {
    static let map = GameSounds()

    // The engine's, 0-8 in every world's table.

    /// 0: the player picks up an object (the level's code sees HELD_OBJECT change).
    let pickUp = Sound(.tone, length: 0x06, sweep: 0x45, pitch: 0x22)
    /// 1: the player puts it down.
    let drop = Sound(.tone, length: 0x06, sweep: 0xC5, pitch: 0x22)
    /// 2: a robot's bumper touches something.
    let bumper = Sound(.tone, length: 0x06, sweep: 0x46, pitch: 0x8A, guess: true)
    /// 3: a robot's grabber takes hold of an object (links it to the robot).
    let grab = Sound(.tone, length: 0x04, sweep: 0x80, pitch: 0x04, guess: true)
    /// 4: a grabber lets go.
    let release = Sound(.noise, length: 0x00, sweep: 0x31, pitch: 0x09, guess: true)
    /// 5: a robot's antenna object turns colour 5.
    let antenna = Sound(.tone, length: 0x00, sweep: 0x80, pitch: 0x09, guess: true)
    /// 6: the wiring code ($F000): a wire's end is attached or taken off.
    let solder = Sound(.noise, length: 0x02, sweep: 0x0B, pitch: 0x1B, guess: true)
    /// 7: an energy crystal recharges a robot's battery (CRYSTALS, in the robot's interior).
    let recharge = Sound(.tone, length: 0x6E, sweep: 0x80, pitch: 0x55)
    /// 8: a used crystal (colour 7) at its place turns colour 5 (CRYSTALS).
    let crystal = Sound(.tone, length: 0x49, sweep: 0x69, pitch: 0xCA, guess: true)

    // The levels' and the kit's (9-11).

    /// 9: leaving a level, after `exitTones`.
    let levelExit = Sound(.noise, length: 0x71, sweep: 0x41, pitch: 0x92)
    /// Levels 1-4's exit rooms, every 6 ticks while the player stands on the
    /// exit: pitch step × 16 + 8, step counting up by 2 from 1 (Level 1) or
    /// 0 (Levels 2-4) until it reaches 9; not in a table.
    let exitTones = Sound(.tone, length: 0x2A, sweep: 0x37, pitch: 0x28, 0x38, 0x48, 0x58, 0x68, 0x78, 0x88, 0x98, 0xA8)
    /// 10 and 11: the code Levels 1, 2, 3 and 5 and the Toolkit share.
    let sound10 = Sound(.tone, length: 0x0A, sweep: 0x2D, pitch: 0x24)
    let sound11 = Sound(.tone, length: 0x0A, sweep: 0xAC, pitch: 0x24)

    // Each world's own, from 12 (the lab's from 9).

    let level3Sound12 = Sound(.noise, length: 0x21, sweep: 0x19, pitch: 0x78)
    let level3Sound13 = Sound(.tone, length: 0x1F, sweep: 0x17, pitch: 0x3A)
    let level3Sound14 = Sound(.noise, length: 0x18, sweep: 0x99, pitch: 0x17)
    let level4Sound12 = Sound(.noise, length: 0x0B, sweep: 0x2E, pitch: 0x16)
    let level4Sound13 = Sound(.noise, length: 0x07, sweep: 0x0C, pitch: 0x7D)
    let level4Sound14 = Sound(.noise, length: 0x03, sweep: 0x00, pitch: 0x03)
    let level4Sound15 = Sound(.noise, length: 0x7D, sweep: 0xFF, pitch: 0x10)
    let level4Sound16 = Sound(.tone, length: 0x06, sweep: 0x2B, pitch: 0x1A)
    let level4Sound17 = Sound(.tone, length: 0x3B, sweep: 0x00, pitch: 0x00)
    let level5Sound12 = Sound(.noise, length: 0x6F, sweep: 0x80, pitch: 0xC8)
    let level5Sound13 = Sound(.noise, length: 0x4C, sweep: 0xC4, pitch: 0x10)
    let level5Sound14 = Sound(.noise, length: 0x20, sweep: 0x04, pitch: 0x07)
    /// Robot Anatomy and Toolkit.
    let kitSound12 = Sound(.tone, length: 0x00, sweep: 0x29, pitch: 0x21)
    /// Robot Anatomy and Toolkit's 13, the lab's and its tutorial's 11.
    let kitSound13 = Sound(.tone, length: 0x03, sweep: 0x00, pitch: 0xD2)
    /// The Innovation Lab and its tutorial.
    let labSound9 = Sound(.tone, length: 0x09, sweep: 0x37, pitch: 0x68)
    let labSound10 = Sound(.noise, length: 0x0B, sweep: 0x52, pitch: 0x16)
}

extension GameSounds {
    /// Every sound with its name (the property's), in declaration order.
    static let named: [(name: String, sound: Sound)] = Mirror(reflecting: map).children.compactMap { child in
        guard let label = child.label, let s = child.value as? Sound else { return nil }
        return (label, s)
    }

    /// Every pitch of every sound with its name and parameters.
    static let pitches: [(name: String, parameters: Sound.Parameters)] = named.flatMap { name, sound in
        sound.pitches.map { pitch in
            (sound.pitches.count == 1 ? name : name + String(format: "_%02X", pitch),
             Sound.Parameters(kind: sound.kind, length: sound.length, sweep: sound.sweep, pitch: pitch))
        }
    }

    /// The name of the sound with these parameters, nil if the map has none.
    static func name(for parameters: Sound.Parameters) -> String? { byParameters[parameters] }

    private static let byParameters = Dictionary(pitches.map { ($0.parameters, $0.name) }, uniquingKeysWith: { a, _ in a })
}
