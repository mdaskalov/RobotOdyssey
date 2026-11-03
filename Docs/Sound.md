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
`GameSounds` (RobotOdyssey/Symbols/GameSounds.swift); a name with `?` below
is a guess there (`guess: true`). The engine's addresses are the levels'.

| # | Name | Parameters | Who | |
|---|---|---|---|---|
| 0 | grab | tone $06 $45 $22 | every world's code | HELD_OBJECT changes to an object |
| 1 | drop | tone $06 $C5 $22 | every world's code | … to none |
| 2 | bumper | tone $06 $46 $8A | $D25C | a robot's bumper touches something |
| 3 | robotGrab | tone $04 $80 $04 | $DC7F | a robot's grabber (its hand) links an object to the robot |
| 4 | robotRelease | noise $00 $31 $09 | $DB22 | … lets go (confirmed by ear, 2026‑11‑03) |
| 5 | antenna | tone $00 $80 $09 | $DD56 | a robot's antenna object turns colour 5 |
| 6 | solder | noise $02 $0B $1B | $F000 (4×) | the soldering pen: a wire's end soldered to a pin or unsoldered (confirmed by ear, 2026‑11‑03) |
| 7 | crystalDischarge | tone $6E $80 $55 | $DF76 (CRYSTALS) | a crystal discharges into a robot's battery: ROBOT_BATTERY = $0F, the crystal used (colour 7) |
| 8 | crystalCharge | tone $49 $69 $CA | $DF0F (CRYSTALS) | a used crystal (colour 7) at its place charges again: colour 5 |
| 9 | levelExit | noise $71 $41 $92 | levels 1‑4 | leaving the level, after the exit tones |
| – | exitTones | tone $2A $37 *n* × 16 + 8 | levels 1‑4 | while the player stands on the exit (Level 1: room $2A at (32, 32)), every 6 ticks, *n* counting up by 2 from 1 (Level 1) or 0 (2‑4) until 9: written to slot 0 directly |
| 10, 11 | sentryGrab, sentryDrop | tone $0A $2D/$AC $24 | levels 1, 2, 3, 5, Toolkit | the sentries' shared code (Level 1: L1_SENTRIES $1305, sounds at $1688 and $1718): a sentry seizes the player or a robot that came into its room (10, rising like grab), carries it back to where it came in and lets go (11, falling like drop) |
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
6 and 7) and notes the cycle of every click (the last of `LDA SPEAKER`,
where it reads $C030, as the CPU does since 2026‑11‑03; before, the cycle
after it). It
reports the cycles as `Engine.elapsed`, which `Machine` adds to the CPU's: a
tick with a sound takes as long as on the Apple. The first native that does;
the others take no time, so the game runs faster with them (Engine.md).

Each sound played (`Sound.Played`: parameters, name from the map, start cycle,
cycles, clicks) goes to `Machine.takeSounds()`. `GameLoop.takeSpeaker()`
hands them over with every click to the cycle: theirs, and those of the 6502
code that reads $C030 itself (the loader's bell, the menu's and the intro's
tunes, and the game's own PLAY_SOUNDS when its native is switched off),
which `Machine` records. The viewer (`ViewerModel`) takes them after each
step and plays them (`SoundPlayer`, AVAudioEngine): `SpeakerRenderer` makes
the speaker's sound from the clicks – the cone moves to its other side at
each click; the square wave is averaged over each 44.1 kHz sample and the DC
is taken out (a high pass at about 35 Hz, which lets the cone settle 50 ms
after the sound). The loop's pacing keeps a target cycle, so after a
sound's cycles the loop waits until the clock has caught up: the game stops
while the sound plays, as on the Apple. *Sound* in the toolbar mutes the
Mac; Ctrl‑S is the game's own.

**The stream** (`SpeakerStream`): after each step the samples are made up
to the cycle the machine has reached, the cone and the high pass going on
from where they were, so a tune taken in the viewer's 1/60 s steps is the
tune rendered at once (`Data/loader_check.sh` checks it on the intro). A
stretch of sound goes on through silences of up to 0.25 s (the intro's
pauses within a tune are below 50 ms, between tunes 0.33‑0.78 s); after that
the stream rests and the next click starts a new stretch at once – a sound
of the native, rendered whole as it is taken, is heard with the page it
belongs to, as before. A stretch rendered step by step (the loader runs by
the clock) starts with 40 ms of silence, so a late step doesn't break it.

A stretch must not start ahead of the clock and then wait for it: its
samples run out. The viewer finishes a tick at once, ahead of the clock
(Engine.md, *A tick at once*), up to 10,000 cycles past the flip; the
original PLAY_SOUNDS (its native switched off) plays its sound after the
flip, so until 2026‑11‑03 only the sound's first clicks came with the page,
the rest about 150 ms later, once the clock had caught up – a blip and the
sound again. Now `GameLoop.run` runs on through the sound player's code as
the native takes its cycles, and the two sound alike: the same clicks at
the same times.

Nor may a stretch wait for the clock while the cone still moves: after a
tick finished ahead of the clock its samples ran out a few ms after the
sound's last click, and the player cut the cone off at its swing (0.8 – a
click at the end of every sound, also the native's). Where the loop stops
with nothing to click for a while – at a tick's start, or past its flip and
out of the sound player (`GameLoop.speakerQuiet`) – the stream ends the
stretch with the cone settled, 50 ms after the last click
(`SpeakerRenderer.settle`, down to 1/50,000 of a click's swing; 20 ms left
1/80), even past where the machine is. The next sound starts a new stretch.

The intro's pauses while a picture is drawn are the original's: its
bytecode draws between the tunes (from 17.1 s on a 44 ms pause every
0.29 s, two XOR_BLOCKs; 0.07‑0.34 s for each picture), and the Apple can't
click while it draws. The menu's drawing natives (Loader.md) draw at once,
so with them on the tunes follow one another (the intro 24.0 s instead of
26.0); switched off, the pauses are the Apple's.

So the sound is the original's for every call, to the cycle, noise included,
also for sounds the map doesn't know (they are named by their parameters in
the status).

The viewer's *World* panel lists the world's sound table (`World.sounds`,
read from WORLD_SOUND's routine as `Data/ro_sounds.sh` does) and plays a
sound alone on a machine of its own (`Sound.play`: `Machine.playing` puts it
in the queue as a main loop would, a noise from shift register 0 and Y = 0;
the native PLAY_SOUNDS plays it, or the original code for an unknown
version), through a player of its own beside the game's.

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
