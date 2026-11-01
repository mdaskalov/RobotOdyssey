# Robot Odyssey I (Apple II) – Sound

The game has one sound player in engine main, used by every world and both
versions: a queue of sounds, each a **tone** or a **noise** given by four
bytes, played by two loops that click the speaker ($C030) while the game
waits. Nothing else in the game touches the speaker (the loader clicks once,
at $55BF). The Swift port runs the player as a native routine that reports
every click to the cycle, and the viewer turns the clicks into sound.

## The routines

| Symbol | Address | |
|---|---|---|
| WORLD_SOUND | $0806 | every world's: `JMP` to its own routine that copies sound X of its sound table into slot 0 with room A, then QUEUE_SOUND |
| QUEUE_SOUND | $9F13 | queues slot 0's sound in front of the others (`SOUND_QUEUE` − 1); with 8 queued, nothing |
| PLAY_SOUNDS | $9F3C | Ctrl‑S ($93 in LAST_KEY) toggles SOUND_ON; while on, plays the queue from SOUND_QUEUE to slot 7 and leaves it empty (8) |
| PLAY_TONE | $9EBB | the tone loop |
| PLAY_NOISE | $9E7A | the noise loop |

The queue ($9EEA‑$9F11) has eight slots in five tables: SOUND_LENGTHS,
SOUND_SWEEPS, SOUND_PITCHES, SOUND_FLAGS (bit 7 noise, bit 6 *wrapping*
noise) and SOUND_ROOMS. Slot 0 is where the worlds put a sound before
QUEUE_SOUND, which copies it to the slot in front.

Every main loop calls PLAY_SOUNDS after FLIP_PAGE, with object 0's room set
to CURRENT_ROOM for the call (`LDA OBJ_ROOM / STA … / LDA CURRENT_ROOM / STA
OBJ_ROOM / JSR PLAY_SOUNDS`). A sound is played only if its room is $FF or
that room, so a robot's sounds are heard only in the room the player sees;
the others are dropped. A few places call PLAY_SOUNDS at once after queuing
(the levels' exits).

PLAY_SOUNDS per slot ($9F6A): SOUND_COUNT_HIGH ($54) = length,
SOUND_COUNT_LOW ($53) = 0, SOUND_SWEEP ($56) = sweep, then rotates the flags
out of the slot (`ROL SOUND_FLAGS,X` with the carry the room's compare set,
so the slot is left rotated): bit 7 clear → TONE_PERIOD ($50) = pitch, PLAY_TONE;
set → NOISE_PERIOD ($55) = pitch, then bit 6 clear → PLAY_NOISE, set → it
patches PLAY_NOISE's `LDA NOISE_PERIOD / BEQ` ($9EA3) with four NOPs, plays,
and puts the bytes back. No world uses bit 6.

**PLAY_TONE**: a click at once, then one every TONE_PERIOD loop iterations
(period 0 = 256): a square wave of half period *pitch* × 20‑25 cycles.
SOUND_COUNT_HIGH + 1 blocks of 256 iterations (`DEC / BPL`: up to $80, from
$81 one block). The **sweep**: every (sweep & $7F) iterations the period
grows by 1 if bit 7 is set (the pitch falls), else shrinks by 1 (rises);
sweep 0 none.

**PLAY_NOISE**: a 16‑bit shift register NOISE_HIGH:NOISE_LOW ($52:$51)
shifts left every iteration, taking in bit 15 xor bit 12 (the routine does it
with `ROR A ×3 / EOR NOISE_HIGH / ASL A ×3`: the bit shifted out ends up in
bit 5, so A's other bits, the floating bus's $C030 value included, don't
matter). Once NOISE_PERIOD iterations have passed, the next iteration that
shifts out a 1 clicks. (Length + 1) & $FF blocks of 256 iterations (256 for
$FF). The sweep works as the tone's, but a falling period stops at 0 (unless
wrapping), and its counter is **Y as PLAY_SOUNDS was called with** – the
noise loop never sets it. In the main loops Y comes from FLIP_PAGE: 0 or 2,
by the page.

So a tone depends only on its four bytes; a noise also on the shift register
(it goes on from the last noise) and on Y. The game stops while a sound
plays: the longest take almost 2 s (1.9 M cycles).

## The sounds

Each world has its sound table in its own code: four tables of 12‑18 bytes
(flags, length, sweep, pitch) after one another, read by its WORLD_SOUND
routine (Level 1: L1_QUEUE_TABLE_SOUND $0944, tables at $18B2). Numbers 0‑8
are the same in every world and are the engine's; the engine queues them with
`LDX #n / LDA room / JSR WORLD_SOUND`. The map of the sounds is
`GameSounds` (RobotOddyssey/Symbols/GameSounds.swift); a name with `?` below
is a guess there (`guess: true`). The engine's addresses are the levels'.

| # | Name | Parameters | Who | |
|---|---|---|---|---|
| 0 | pickUp | tone $06 $45 $22 | every world's code | HELD_OBJECT changes to an object |
| 1 | drop | tone $06 $C5 $22 | every world's code | … to none |
| 2 | bumper ? | tone $06 $46 $8A | $D25C | a robot's bumper touches something |
| 3 | grab ? | tone $04 $80 $04 | $DC7F | a grabber links an object to the robot |
| 4 | release ? | noise $00 $31 $09 | $DB22 | … lets go |
| 5 | antenna ? | tone $00 $80 $09 | $DD56 | a robot's antenna object turns colour 5 |
| 6 | solder ? | noise $02 $0B $1B | $F000 (4×) | the wiring: a wire's end attached or taken off |
| 7 | recharge | tone $6E $80 $55 | $DF76 (CRYSTALS) | a crystal in a robot's battery: ROBOT_BATTERY = $0F |
| 8 | crystal ? | tone $49 $69 $CA | $DF0F (CRYSTALS) | a used crystal (colour 7) at its place turns colour 5 |
| 9 | levelExit | noise $71 $41 $92 | levels 1‑4 | leaving the level, after the exit tones |
| – | exitTones | tone $2A $37 *n* × 16 + 8 | levels 1‑4 | while the player stands on the exit (Level 1: room $2A at (32, 32)), every 6 ticks, *n* counting up by 2 from 1 (Level 1) or 0 (2‑4) until 9: written to slot 0 directly |
| 10, 11 | sound10, sound11 | tone $0A $2D/$AC $24 | levels 1, 2, 3, 5, Toolkit | their shared code around $8EF0's rooms |
| 12‑14 | level3Sound12‑14 | | Level 3 | |
| 12‑17 | level4Sound12‑17 | | Level 4 | |
| 12‑14 | level5Sound12‑14 | | Level 5 (its table is in the world image, $7AC0) | |
| 12, 13 | kitSound12, 13 | | Robot Anatomy, Toolkit | |
| 9‑11 | labSound9, labSound10, kitSound13 | | the lab and its tutorial | |

37 sounds with the exit tones' nine pitches. No world writes its table, so
the map covers everything the worlds queue; Data/ro_sounds.sh checks every
world's table against it.

## The port

`Engine.playSounds` (Engine/Speaker.swift) is the native PLAY_SOUNDS, with
PLAY_TONE and PLAY_NOISE. It runs their loops as they are – counters, sweep,
shift register, Y – so memory and registers are the original's, counts
every instruction's cycles (two of the queue's tables cross a page for slots
6 and 7) and notes the cycle of every click (the end of `LDA SPEAKER`). It
reports the cycles as `Engine.elapsed`, which `Machine` adds to the CPU's: a
tick with a sound takes as long as on the Apple. The first native that does;
the others still take no time (Engine.md).

Each sound played (`Sound.Played`: parameters, name from the map, start cycle,
cycles, clicks) goes to `Machine.takeSounds()`, `GameLoop.takeSounds()`. The
viewer (`ViewerModel`) takes them after each step and plays them
(`SoundPlayer`, AVAudioEngine): `SpeakerRenderer` makes the speaker's sound
from the clicks – the cone moves to its other side at each click; the square
wave is averaged over each 44.1 kHz sample and the DC is taken out (a high
pass at about 35 Hz, which lets the cone settle 20 ms after the sound). The
loop's pacing keeps a target cycle, so after a sound's cycles the loop waits
until the clock has caught up: the game stops while the sound plays, as on
the Apple. *Sound* in the toolbar mutes the Mac; Ctrl‑S is the game's own.

So the sound is the original's for every call, to the cycle, noise included,
also for sounds the map doesn't know (they are named by their parameters in
the status).

## Verification

* `Data/native_check.sh`: PLAY_SOUNDS called directly on random queues (up
  to 8 sounds of the map or random ones, wrapping noise included, rooms, the
  sound on or off, Ctrl‑S, random counters, Y and shift register), 120 per
  world: memory, A, X, Y, flags, the cycles and every click identical –
  v1.1 1.45 M clicks, v1.0 1.18 M. Every sound played in the tick runs must be
  in the map.
* `Data/ro_sounds.sh DISK.dsk…`: every world's table by name, and every sound
  of the map run by the original code and by the native: same cycles, same
  clicks. With `--wav DIR` it writes them as WAV files to listen to
  (a noise from shift register 0 and Y = 0).
