# Robot Odyssey I (Apple II) – Engine Notes

Runs on a 128K Apple IIe but uses only the 64K main RAM (aux is untouched),
including the language card. Graphics: hi‑res, double buffered (pages 1 and
2, flipped every tick by $AEED). Input: keyboard, joystick/paddles
($C061‑$C065, $C070). Sound: speaker $C030. The engine looks for a
joystick at $AC24 (paddle 0's timer must run out after the $C070 strobe);
without one it plays by keyboard.

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
($F04B), chips at $F56B: it runs the program of each of the 8 chips (chip
*n* at $D000 + $400*n*, program from +8; chips 0‑3 in language card bank 1)
up to opcode 7, so an empty chip must hold `07 FF FF FF` – the loader's job
(DiskLayout.md); with zeros there a tick never ends.

$8DAB mirrors the player's colour (object 0, $6200): 5 normally, 7 (white)
after the toggle at $BEF4; the robot and circuit block runs only at 5. Both
saved games on the sample storage disk are at 7.

## Chips

The chips use the same bytecode as the PC version's CHP files, so Micah
Dowty's disassembler (`Data/ro_chip_disasm.py`, ported to Python 3)
reads them unchanged; `Data/ro_chips.py` finds them on the program disks, in
save states and on storage disks (listing: `Data/Extracted/v1.1/chips.txt`).
v1.0 and v1.1 have the same chips.

A chip is 8 pin bytes (pins 1‑4, then 8‑5) followed by its program. Every
input is a byte *inside* the program holding its current value (0/1); every
output is a list of 16‑bit big‑endian offsets from the chip's start (to pin
bytes or to other parts' input bytes), ended by $FF:

| Opcode | Part | Operands |
|---|---|---|
| 01 / 02 / 03 | AND / OR / XOR | in0 in1, outputs |
| 04 | NOT | in, outputs |
| 05 | flip‑flop | in0 in1 state0 state1, outputs of half 0, outputs of half 1 |
| 06 | nested chip | a whole chip inline (its offsets relative to its own start) |
| 07 | end | lists *source, destinations…* (wires to and from pins), an empty list ends the chip |

The chip table at **$F008 + 8n** holds chip *n*'s pin directions in the same
order (0 unused, 1 in, 2 out) – the PC CSV files' PIN table. The saved‑game
header keeps it at +$00 (DiskLayout.md).

Chips on the disks (the loaders' set‑up):

* Level 1, kept by levels 2‑5: chip 0 ($D000, 426 bytes; pins 1‑2 in, 3‑8
  out): 2 flip‑flops, 2 ANDs, a NOT and 5 nested chips of one flip‑flop each.
  Chip 1 ($D400, 386 bytes; pins 2, 4, 6, 8 in, 1, 3, 5, 7 out): ORs, ANDs, a NOT
  and a nested chip with 4 flip‑flops.
* Innovation Lab Tutorial: chip 0 ($D000, 17 bytes, pin 1 out) is a NOT
  whose output feeds its own input and pin 1 (a clock); chip 2 ($D800) is
  Level 1's chip 1.

The disassembler's notes on evaluation (PC version: parts run in program
order, outputs to the current chip's pins or nodes propagate at once, others
are queued until just before the nodes; flip‑flops in chips don't toggle with
both inputs high; one extra tick of delay across a nested chip's pins) are
still to be checked against $F56B.

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
MAIN_LOOP and the cycle counter.) `GameLoop` on the worlds built from the
disks agrees: Level 1's room $28 takes 200‑208 K cycles per tick, 5.0
ticks/s.

What matters for circuits is **the tick**: every robot, sensor, wire, gate
and chip is updated exactly once per tick in a fixed order, and nothing in
the simulation looks at wall‑clock time. A port that keeps the per‑tick
update order bit‑exact keeps every circuit working, whatever the tick rate.
The wall‑clock rate is a separate, user‑visible choice:

* **Authentic** – compute each tick's cycle cost (or run the original code)
  and pace ticks at 1.0205 MHz, reproducing the room‑dependent speed. The
  viewer does this.
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
  bank 1 every tick. Worlds built from the disks get bank 1 (and chips 4‑7 at
  $E000‑$EFFF, the chip table at $F008) from the loader's set‑up after
  loading the world (`ChipSetup`, DiskLayout.md): Level 1, and with it levels
  2‑5, gets two chips (167 → $D000, 165 → $D400 – the Level 1 save state
  holds exactly these), the lab tutorial two others, the lab only empty
  chips; saved games bring their own.
* soft switches: keyboard $C000/$C010, display page $C054/$C055, speaker
  $C030; buttons read 0 and the paddle timers never run out – no joystick,
  so the engine plays by keyboard. (Timers that run out at once read as a
  joystick held up‑left: the player walks off.)
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

`GameLoop` runs the main loop from there as in the game, with no input:
it is run by CPU cycles and the page on screen ($C054/$C055) is what the
Apple shows, so each tick takes as long as its work. To watch any room, the
selected room replaces the player's in `CUR_ROOM` when the loop arrives at
the draw phase, and the loop's own value goes back before the page flip, so
the rest of the tick (including the `$6300 ↔ CUR_ROOM` swap around $9F3C)
sees what the game would. Watching the player's room changes nothing
(checked tick by tick on every world); elsewhere only what the draw phase
writes differs. A room change shows the room at once, drawn on a copy of the
machine at the start of the tick (`preview`). All eleven worlds (nine from
the v1.1 disks, two saved games) run 100 ticks with the player standing
still; v1.0 needs its own file lengths (`GameCatalog.lengthsV10`: its
level engine is one byte longer, and that byte is code).

## Porting strategy

1. **Reference engine** – the original code on `CPU6502` in `Machine`, with
   the language‑card banking (done: whole ticks in `GameLoop`; next: input).
   This gives golden traces: the world memory after every tick for a given
   input sequence.
2. **Native engine** – port the engine routine by routine as native routines
   of the hybrid engine (above): input, player movement, grabbing, linked
   objects, robots (thrusters, bumpers, antennas, grabbers, sensors,
   batteries), wires, gates, chips, room transitions. Started with the robot
   drawing.
3. **Lock‑step tests** – `Data/native_check.sh` compares every native routine
   with the original, per call on random states, per drawn frame and over
   whole ticks (each world's main loop, 40 ticks: all memory, bank 1 and the
   page on screen after every tick); next, feed the same input to both;
   any difference points to the routine to fix.
4. **Level and room code** ($0803 code, $8EF0 segments, code rooms) stays
   original 6502 code: it is world‑specific puzzle logic that pokes the same
   tables, and running it as is cannot break it.
