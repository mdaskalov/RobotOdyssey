# Robot Odyssey I (Apple II) – Engine Notes

Runs on a 128K Apple IIe but uses only the 64K main RAM (aux is untouched),
including the language card. Graphics: hi‑res, double buffered (pages 1 and
2, flipped every tick by $AEED). Input: keyboard, joystick/paddles
($C061‑$C065, $C070). Sound: speaker $C030.

## Memory map while playing

| Range | Contents |
|---|---|
| $0000‑$03FF | zero page, stack, $02D0‑$02D2 menu/level state, $03F2 reset vector |
| $0800‑$1FFF | **level code** (from $0803; main loop at $0841 in Level 1) and engine piece $1A50 |
| $2000‑$3FFF | hi‑res page 1 |
| $4000‑$5FFF | hi‑res page 2 (the loader/menu runs here between worlds) |
| $6000‑$94FF | **the world** – see WorldFormat.md |
| $9500‑$B7D6 | engine main: font, colour tables, drawing, text, objects |
| $B8E0‑$BFFF | engine piece |
| $C000‑$C0FF | I/O |
| $D000‑$DFFF | language card bank 2: engine code; bank 1: data (saved with the game) |
| $E000‑$EFFF | language card RAM: data (saved with the game) |
| $F000‑$FFFF | language card: engine code |

The level code differs per world. Its start‑up ($0816) sets engine vectors
(e.g. the draw routine at $AEEB) and ends with `LDA #0 / STA $9C51` right
before the main loop. Leaving a level goes through a handler
(`LDA #2 / STA $02D0 / STY $02D1 / … / JMP ($03F2)`) back to the loader.

## The tick (Level 1 main loop, $0841‑$091C)

One loop iteration is one game tick. In order (names from
`Data/RobotOdyssey.sym`; `_Q` = guess):

```
$A90C READ_INPUT_Q        $0963 L1_KEY_COMMANDS      $DFA3 PLAYER_MOVE_Q
$BEBC GRAB_BUTTON_Q       $1A50 KEY_T_HANDLER        $FE18 SAVE_MOVE_DELTA
$1AB0 / $A5CD (only when $8DAA = 0)                  $0920 L1_HELD_CHANGED_Q
$9C53 MOVE_LINKED_OBJECTS $BED6 / $BDE1 GRAB_LOGIC_Q $FE25 (if $8ED8 = $FF)
$DE95 / $DF81 CRYSTALS_Q  $0CA8 / $918B / $10F8 level specific
$D000 ROBOTS_RESET_Q      (if $8DAB = 5 – which it is on every tick of normal play:
                           $D832 thrusters, $DA90, $DE10, $F0CC wires, $F04B gates,
                           $F56B chips)
$F5A9  $1740 (level)      $DD59 PLAYER_IN_ROBOT
--- draw on the hidden page ---
$9D03 DRAW_ROOM_TILES     $A2A2 DRAW_ROOM_TEXTS      $1305 (level)
$9D18 DRAW_ROOM_OBJECTS   $101A (level)  $D2BC DRAW_ROBOTS  $D72B DRAW_ROBOT_INTERIOR
$187C $0C06 $8F69 $0F93 (level)  $DDD0  $1E3B
$F7BE/$F5C2 (if $8DAA = $FD)    $FC62 DRAW_WIRES  $F44D SENSORS_Q  $DA44
$A6AD (if $8DAA = 0 and $8E95 = $FF)   $AEED FLIP_PAGE
$9F3C (sound toggle) with the player's room swapped in
```

The circuit is evaluated once per tick: wires copy the colour (signal) of
their source ($F0CC), gates are evaluated from a type table at $8CB7
($F04B), chips at $F56B.

## Timing

The engine never waits for the vertical blank: a tick takes as long as its
work, mostly redrawing the whole room. Measured with `Data/ro_timing.py`
(Level 1 save state on the emulator, no input, 1.0205 MHz):

| Room | Objects | Cycles/tick | Ticks/s |
|---|---|---|---|
| $04, $14, $1F (maze) | 2‑4 | 150‑156 K | 6.5‑6.8 |
| $2C | 7 | 165 K | 6.2 |
| $01 (text) | 2 | 186 K | 5.5 |
| $28 (welcome, much text) | 2 | 200 K | 5.1 |
| $02 (three robots) | 8 | 229 K | 4.5 |
| $09 / $0A (robot interiors) | 20‑28 | 254‑270 K | 3.8‑4.0 |

So the original runs at roughly **4‑7 ticks per second**, varying by room.
(Measured without joystick reads; the paddle read loops add up to ~3 ms per
read on real hardware. Worth confirming in Mariani with a breakpoint on
MAIN_LOOP and the cycle counter.)

What matters for circuits is **the tick**: every robot, sensor, wire, gate
and chip is updated exactly once per tick in a fixed order, and nothing in
the simulation looks at wall‑clock time. A port that keeps the per‑tick
update order bit‑exact keeps every circuit working, whatever the tick rate.
The wall‑clock rate is a separate, user‑visible choice:

* **Authentic** – compute each tick's cycle cost (or run the original code)
  and pace ticks at 1.0205 MHz, reproducing the room‑dependent speed.
* **Fixed** – a constant rate (e.g. 5 or 6 ticks/s), smoother but not
  identical in feel.
* **Fast** – for testing circuits.

## The draw phase

Every world's main loop draws between `LDA $6300 / STA $9C2D / JSR …` (the
current room is the player's room; the JSR is $DD59 PLAYER_IN_ROBOT in the
levels, $DC16 in Anatomy/Toolkit, $DBAF in the lab worlds) and `JSR $AEED`
(FLIP_PAGE). In between come the engine's drawing routines and the world's
own (Level 1: $1305, $101A, $187C, $0C06, $8F69, $0F93; Robot Anatomy's
$09CD; Level 5's code rooms via $7294 …). `DrawPhase` (Machine.swift) finds
these bounds and the main loop's first instruction in any world.

## The hybrid engine (Swift)

The game runs as the original 6502 code on `CPU6502`, inside `Machine`:

* 64K main RAM plus language card bank 1 (engine data, chips): a switch via
  $C080‑$C08F swaps $D000‑$DFFF. The chips ($F56B) and sensors ($F44D) use
  bank 1 every tick. Worlds built from the disks get bank 1 from loader files
  167 → $D000 and 165 → $D400 (the Level 1 save state holds exactly these);
  saved games bring their own.
* soft switches: keyboard $C000/$C010, display page $C054/$C055, speaker
  $C030; buttons and paddles read 0.
* **native routines**: a Swift function registered at an engine entry point
  runs when the 6502 code reaches it (CPU traps) and returns like RTS. It
  works on the same memory (`RAM`), takes its parameters where the 6502 code
  does and must leave memory **byte for byte** as the original leaves it,
  temporaries included (registers are not reproduced). It is installed only
  if the MD5 of the original code matches, so other builds or versions fall
  back to emulation.

So level and room code always runs as the original code, and engine
routines become Swift one at a time. Ported so far: the robot drawing
($D2BC/$D72B and the kit/lab equivalents) with the primitives it uses
(sprite, plot, lines, box) – see Robots.md.

`GameScreen` uses this for the viewer: it runs the world's start‑up code
($0803 up to the main loop) once, then for any room sets $9C2D and runs the
draw phase, so rooms look exactly as in the game, including what the world's
own code draws. A world built from the disks starts with the random generator
at $4E/$4F = 0, which it never leaves; `GameScreen` seeds it (Robots.md).

## Porting strategy

1. **Reference engine** – the original code on `CPU6502` in `Machine`, with
   the language‑card banking (done for drawing; next: whole ticks with input).
   This gives golden traces: the world memory after every tick for a given
   input sequence.
2. **Native engine** – port the engine routine by routine as native routines
   of the hybrid engine (above): input, player movement, grabbing, linked
   objects, robots (thrusters, bumpers, antennas, grabbers, sensors,
   batteries), wires, gates, chips, room transitions. Started with the robot
   drawing.
3. **Lock‑step tests** – `Data/native_check.sh` compares every native routine
   with the original, per call on random states and per drawn frame; next,
   feed the same input to both for whole ticks and compare the world
   ($6000‑$94FF, $D000‑$EFFF) after every tick; any difference points to the
   routine to fix.
4. **Level and room code** ($0803 code, $8EF0 segments, code rooms) stays
   original 6502 code: it is world‑specific puzzle logic that pokes the same
   tables, and running it as is cannot break it.
