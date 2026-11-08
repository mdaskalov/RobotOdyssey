import Foundation
import MOS6502

/// Native port of the engine's sound (Docs/Sound.md): PLAY_SOUNDS ($9F3C)
/// plays the queued sounds with PLAY_TONE ($9EBB) and PLAY_NOISE ($9E7A),
/// which click the speaker ($C030) in loops while the game waits: a long
/// sound stops the game for a second.  The worlds queue sounds with
/// WORLD_SOUND or straight into slot 0 and QUEUE_SOUND, and every main loop
/// calls PLAY_SOUNDS after the page flip, with object 0's room set to
/// CURRENT_ROOM.
///
/// The native leaves memory and registers as the original does and takes
/// its time, to the cycle (`elapsed`): the loops run as they do, counting
/// cycles, and note each click by the cycle the original reads the speaker
/// at, the last of `LDA SPEAKER` (`sounds`), for `SpeakerRenderer`.
nonisolated extension Engine {
    /// PLAY_SOUNDS ($9F3C): Ctrl-S turns the sound off and on.  While it is
    /// on, plays the queued sounds from SOUND_QUEUE on, each that is for
    /// object 0's room or for every room ($FF), and empties the queue.
    mutating func playSounds() {
        while true {
            r.a = m.lastKey
            r.compare(r.a, 0x93)
            elapsed += 6                                // LDA LAST_KEY, CMP #$93
            if r.zero {
                m.lastKey = 0
                m.soundOn = (m.soundOn ^ 1) & 1
                elapsed += 20                           // BNE, LDA #0, STA, LDA, EOR, AND, STA
            } else {
                elapsed += 3
            }
            r.a = r.nz(m.soundOn)
            elapsed += 4
            guard !r.zero else {
                elapsed += 3 + 6                        // BEQ, RTS
                return
            }
            r.x = m.soundQueue
            r.compare(r.x, 8)
            elapsed += 2 + 4 + 2                        // BEQ, LDX, CPX
            guard !r.zero else {
                elapsed += 3 + 6
                return
            }
            let slot = Int(r.x)
            let room = m.soundRooms[slot]
            elapsed += 2 + 4 + crossing(\.soundRooms, slot) + 2     // BEQ, LDA SOUND_ROOMS,X, CMP #$FF
            if room == 0xFF {
                elapsed += 3
                playSound(slot)
            } else if room == m.objRoom[0] {
                elapsed += 2 + 4 + 2                    // BEQ, CMP OBJ_ROOM, BNE
                playSound(slot)
            } else {
                elapsed += 2 + 4 + 3
            }
            m.soundQueue &+= 1
            elapsed += 6 + 3                            // INC SOUND_QUEUE, JMP PLAY_SOUNDS
        }
    }

    /// Queue slot `slot`'s sound ($9F6A).  The flags are rotated out of the
    /// slot (with the carry the room's compare set): bit 7 noise, then bit 6
    /// wrapping noise, for which PLAY_SOUNDS patches PLAY_NOISE and back.
    private mutating func playSound(_ slot: Int) {
        let flags = m.soundFlags[slot]
        let parameters = Sound.Parameters(kind: Sound.Kind(flags: flags), length: m.soundLengths[slot],
                                          sweep: m.soundSweeps[slot], pitch: m.soundPitches[slot])
        m.soundCountHigh = parameters.length
        m.soundCountLow = 0
        m.soundSweep = parameters.sweep
        r.a = parameters.pitch
        m.soundFlags[slot] = flags << 1 | 1
        elapsed += 4 + crossing(\.soundLengths, slot) + 3 + 2 + 3     // LDA, STA, LDA #0, STA
            + 4 + crossing(\.soundSweeps, slot) + 3 + 4 + crossing(\.soundPitches, slot) + 7    // LDA, STA, LDA, ROL
        let start: UInt64
        let took: UInt64
        var clicks: [UInt32] = []
        switch parameters.kind {
        case .tone:
            m.tonePeriod = r.a
            elapsed += 2 + 3 + 6                        // BCS, STA TONE_PERIOD, JSR
            start = elapsed
            took = playTone(clicks: &clicks)
            elapsed += took + 3                         // JMP
        case .noise:
            m.noisePeriod = r.a
            m.soundFlags[slot] = flags << 2 | 3
            elapsed += 3 + 3 + 7 + 2 + 6                // BCS, STA NOISE_PERIOD, ROL, BCS, JSR
            start = elapsed
            took = playNoise(wrapping: false, clicks: &clicks)
            elapsed += took + 3
        case .noiseWrapping:
            m.noisePeriod = r.a
            m.soundFlags[slot] = flags << 2 | 3
            elapsed += 3 + 3 + 7 + 3 + 2 + 4 * 4 + 6    // BCS, STA, ROL, BCS, LDA #$EA, 4 STA, JSR
            start = elapsed
            took = playNoise(wrapping: true, clicks: &clicks)
            elapsed += took + 4 * (2 + 4)               // LDA #, STA: PLAY_NOISE back as it was
            r.a = 0x0A
        }
        sounds.append(Sound.Played(parameters: parameters, name: GameSounds.name(for: parameters),
                                   start: cycles + start, cycles: took, clicks: clicks))
    }

    /// PLAY_TONE ($9EBB): a square wave, a click every TONE_PERIOD loop
    /// iterations (the first at once), for SOUND_COUNT_HIGH + 1 blocks of 256
    /// iterations (to $80; from $81 on one block).  Every (sweep & $7F)
    /// iterations the period grows by 1 (sweep bit 7) or shrinks.  Returns the
    /// cycles it takes; the clicks' cycles go to `clicks`.
    mutating func playTone(clicks: inout [UInt32]) -> UInt64 {
        let sweep = m.soundSweep
        var period = m.tonePeriod
        var low = m.soundCountLow, high = m.soundCountHigh
        var x = period
        var y = sweep & 0x7F
        var cycles: UInt64 = 14                         // LDA, AND, TAY, LDX, LDA SPEAKER
        clicks.append(UInt32(cycles - 1))               // the read: LDA SPEAKER's last cycle
        repeat {
            repeat {
                x &-= 1
                if x != 0 {
                    cycles += 2 + 3                     // DEX, BNE
                } else {
                    x = period
                    cycles += 2 + 2 + 3 + 4             // DEX, BNE, LDX TONE_PERIOD, LDA SPEAKER
                    clicks.append(UInt32(cycles - 1))
                }
                cycles += 3                             // LDA SOUND_SWEEP
                if sweep == 0 {
                    cycles += 3
                } else {
                    y &-= 1
                    if y != 0 {
                        cycles += 2 + 2 + 3             // BEQ, DEY, BNE
                    } else if sweep & 0x80 != 0 {
                        period &+= 1
                        y = sweep & 0x7F
                        cycles += 2 + 2 + 2 + 2 + 3 + 5 + 2 + 2     // BEQ, DEY, BNE, TAY, BMI, INC, AND, TAY
                    } else {
                        period &-= 1
                        y = sweep
                        cycles += 2 + 2 + 2 + 2 + 2 + 5 + 2 + 3     // BEQ, DEY, BNE, TAY, BMI, DEC, TYA, BNE
                    }
                }
                low &-= 1
                cycles += low != 0 ? 5 + 3 : 5 + 2      // DEC SOUND_COUNT_LOW, BNE
            } while low != 0
            high &-= 1
            cycles += high & 0x80 == 0 ? 5 + 3 : 5 + 2  // DEC SOUND_COUNT_HIGH, BPL
        } while high & 0x80 == 0
        m.tonePeriod = period
        m.soundCountLow = low
        m.soundCountHigh = high
        r.x = x
        r.y = y
        return cycles + 6                               // RTS
    }

    /// PLAY_NOISE ($9E7A): the shift register NOISE_HIGH, NOISE_LOW moves on
    /// every loop iteration, taking in its bit 15 xor bit 12; once
    /// NOISE_PERIOD iterations have passed, the next one that shifts out a 1
    /// clicks.  SOUND_COUNT_HIGH + 1 blocks of 256 iterations (256 for $FF).
    /// The sweep changes the period as PLAY_TONE's does, with Y as it comes
    /// for its counter; a falling period stops at 0 unless `wrapping`.
    /// Returns the cycles it takes; the clicks' cycles go to `clicks`.
    mutating func playNoise(wrapping: Bool, clicks: inout [UInt32]) -> UInt64 {
        let sweep = m.soundSweep
        var period = m.noisePeriod
        var shift = UInt16(m.noiseHigh) << 8 | UInt16(m.noiseLow)
        var low = m.soundCountLow, high = m.soundCountHigh &+ 1
        var x = period
        var y = r.y
        var feedback = true
        var cycles: UInt64 = 2 + 5 + 3                  // SEC, INC SOUND_COUNT_HIGH, LDX
        repeat {
            repeat {
                let out = shift & 0x8000 != 0
                shift = shift << 1 | (feedback ? 1 : 0)
                cycles += 5 + 5 + 2                     // ROL NOISE_LOW, ROL NOISE_HIGH, TXA
                if x != 0 {
                    x -= 1
                    cycles += 2 + 2                     // BEQ, DEX
                } else {
                    cycles += 3
                }
                if x != 0 {
                    cycles += 3                         // BNE
                } else if out {
                    x = period
                    cycles += 2 + 2 + 4                 // BNE, BCC, LDA SPEAKER
                    clicks.append(UInt32(cycles - 1))
                    cycles += 3                         // LDX NOISE_PERIOD
                } else {
                    cycles += 2 + 3                     // BNE, BCC
                }
                // ROR A three times puts the bit shifted out at bit 5, EOR and three ASL take it out.
                feedback = out != (shift & 0x2000 != 0)
                cycles += 3 * 2 + 3 + 3 * 2 + 3 + 3     // ROR, EOR NOISE_HIGH, ASL, PHP, LDA SOUND_SWEEP
                if sweep == 0 {
                    cycles += 3
                } else {
                    y &-= 1
                    if y != 0 {
                        cycles += 2 + 2 + 3
                    } else if sweep & 0x80 != 0 {
                        period &+= 1
                        y = sweep & 0x7F
                        cycles += 2 + 2 + 2 + 2 + 3 + 5 + 2 + 2
                    } else {
                        y = sweep
                        cycles += 2 + 2 + 2 + 2 + 2     // BEQ, DEY, BNE, TAY, BMI
                        if wrapping {
                            period &-= 1
                            cycles += 4 * 2 + 5 + 2 + 3     // 4 NOP, DEC, TYA, BNE
                        } else if period == 0 {
                            cycles += 3 + 3             // LDA NOISE_PERIOD, BEQ
                        } else {
                            period -= 1
                            cycles += 3 + 2 + 5 + 2 + 3
                        }
                    }
                }
                low &-= 1
                cycles += low != 0 ? 4 + 5 + 3 : 4 + 5 + 2     // PLP, DEC SOUND_COUNT_LOW, BNE
            } while low != 0
            high &-= 1
            cycles += high != 0 ? 5 + 3 : 5 + 2         // DEC SOUND_COUNT_HIGH, BNE
        } while high != 0
        m.noiseLow = UInt8(shift & 0xFF)
        m.noiseHigh = UInt8(shift >> 8)
        m.noisePeriod = period
        m.soundCountLow = low
        m.soundCountHigh = high
        r.x = x
        r.y = y
        return cycles + 6
    }

    /// 1 when `LDA table,X` crosses a page, which takes a cycle more.
    private func crossing(_ table: KeyPath<GameSymbols, Table>, _ x: Int) -> UInt64 {
        (m.address(table) & 0xFF) + x > 0xFF ? 1 : 0
    }
}

// MARK: a sound alone

nonisolated extension Machine {
    /// A machine with `world`'s memory and the sound `p` alone in the queue
    /// (slot 7), as a main loop calls PLAY_SOUNDS with it: the sound on, for
    /// every room.  A noise starts with the shift register at 0 and the
    /// sweep counter (Y) at 0, as FLIP_PAGE leaves it every other tick; in
    /// the game both go on from what came before.
    static func playing(_ p: Sound.Parameters, in world: World, variant: Variant?) -> Machine {
        let machine = Machine(memory: world.mem, bank1: world.bank1, variant: variant)
        let cpu = machine.cpu
        let slot = 7
        cpu.mem[\.soundFlags, slot] = p.kind.rawValue
        cpu.mem[\.soundLengths, slot] = p.length
        cpu.mem[\.soundSweeps, slot] = p.sweep
        cpu.mem[\.soundPitches, slot] = p.pitch
        cpu.mem[\.soundRooms, slot] = 0xFF
        cpu.mem[\.soundQueue] = UInt8(slot)
        cpu.mem[\.soundOn] = 1
        cpu.mem[\.lastKey] = 0
        cpu.mem[\.noiseLow] = 0
        cpu.mem[\.noiseHigh] = 0
        cpu.y = 0
        cpu.sp = 0xF0
        return machine
    }
}

nonisolated extension Sound {
    /// `p` as PLAY_SOUNDS plays it alone in `world` (`Machine.playing`), to
    /// listen to: by the native if the world has it, else by the original code.
    static func play(_ p: Parameters, in world: World) throws -> Played {
        if let check = world.codeCheck, let run = check.natives.first(where: { $0.routine == \.playSounds })?.run {
            let machine = Machine.playing(p, in: world, variant: check.variant)
            if machine.call(run), let played = machine.takeSounds().first { return played }
        }
        return try playOriginal(p, in: world)
    }

    /// `p` by the original code: its clicks by cycle from the entry of
    /// PLAY_TONE or PLAY_NOISE, and the cycles up to its RTS.
    static func playOriginal(_ p: Parameters, in world: World) throws -> Played {
        let machine = Machine.playing(p, in: world, variant: nil)
        let cpu = machine.cpu
        let generators = [GameSymbols.address(\.playTone), GameSymbols.address(\.playNoise)].map { UInt16($0) }
        try cpu.call(UInt16(GameSymbols.address(\.playSounds)), stopAt: Set(generators))
        let start = cpu.cycles
        let sp = cpu.sp
        machine.clicks = []
        while cpu.sp <= sp { try cpu.step() }          // up to its RTS
        return Played(parameters: p, name: GameSounds.name(for: p), start: 0, cycles: cpu.cycles - start,
                      clicks: machine.clicks!.map { UInt32($0 - start) })
    }
}
