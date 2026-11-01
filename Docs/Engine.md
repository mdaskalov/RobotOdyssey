# Robot Odyssey I (Apple II) – Engine Notes

Runs on a 128K Apple IIe but uses only the 64K main RAM (aux is untouched),
including the language card. Graphics: hi‑res, double buffered (pages 1 and
2, flipped every tick by $AEED). Input: keyboard, joystick/paddles
($C061‑$C065, $C070), an Apple mouse card – see "Input". Sound: speaker
$C030.

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
$A90C READ_INPUT          $0963 L1_KEY_COMMANDS      $DFA3 PLAYER_WALK_SPRITE
$BEBC GRAB_BUTTON         $1A50 KEY_T_HANDLER        $FE18 KEEP_MOVE
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
$F7BE SOLDER_WIRE_Q / $F5C2 SOLDER_TOUCH_Q (pen in hand, CopyProtection.md)
$FC62 DRAW_WIRES  $F44D SENSORS_Q  $DA44
$A6AD (if $8DAA = 0 and $8E95 = $FF)   $AEED FLIP_PAGE
$9F3C PLAY_SOUNDS with the player's room swapped in (Sound.md)
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

## Input

**Devices.** At start‑up every world calls DETECT_JOYSTICK ($AC24): if paddle
0's timer runs out after the $C070 strobe, INPUT_DEVICE ($9C3E) = 1
(joystick); else if a slot holds an Apple mouse card ($Cn0C = $20, $CnFB =
$D6), 2; else 0 (keyboard). The keyboard is always read, and in keyboard
mode the paddles are too: the first change of the paddle values switches to
the joystick, a key back to the keyboard. The mouse is read through the
card's firmware ($ACD6).

**READ_INPUT ($A90C)**, the first call of every world's main loop (Level 1
skips it while FLAG_8ED8 is 0):

1. READ_KEY ($AA25): one key per tick from $C000 (strobe cleared), lower‑case
   letters made capitals (AND CASE_MASK $9C21 = $DF) → LAST_KEY ($9C3D), 0 if
   none.
2. READ_JOYSTICK ($AACB), keyboard mode included: strobe $C070, then count
   rounds of a 24‑cycle loop while the timers run, at most 127 (paddle 0
   read 14 cycles after the strobe, paddle 1 at 23; once one has run out the
   loop keeps timing the other). The counts are doubled: PADDLE_X/Y
   ($AAC9/$AACA), STICK_X ($9C39) and STICK_Y ($9C3A, upside down). Buttons:
   button 1 alone → BUTTON_A ($9C3B), button 0 alone → BUTTON_B ($9C3C), both
   → neither. A timer's 2816 cycles at position 255 give 116 rounds, so a
   joystick reaches table entries 0‑14 only.
3. Keyboard: KEY_AS_STICK ($AA40) centres the stick ($80/$80) and looks the
   key up in MOVE_KEYS ($9C13, ten keys each world copies there at start‑up;
   Level 1 from $080B): up, down, left, right, button A, button B, then
   slowly up, down, left, right. A match sets the stick to an extreme ($00,
   $FF) or near the centre ($3F, $C0), or a button, and uses the key up
   (LAST_KEY = 0). A key that is not a movement key stays in LAST_KEY for the
   world's own code.

   | Key (all worlds) | Stick | Move |
   |---|---|---|
   | I / M | y $FF / $00 | 16 up / down |
   | J / K | x $00 / $FF | 7 left / right |
   | Ctrl‑I / Ctrl‑M | y $C0 / $3F | 1 up / down |
   | Ctrl‑J / Ctrl‑K | x $3F / $C0 | 1 left / right |
   | space | button B | |
   | (button A: $01, never typed) | | |

4. The move: MOVE_BY_KEY ($AB54) or MOVE_BY_STICK ($ABA1) look up the stick's
   top four bits: MOVE_DX ($9C22) from $AB71 (keys: −7 −7 −1 −1 0… 1 1 7 7) or
   $ABBE (joystick: −7 −4 −2 −1 −1 −1 0 0 0 0 1 1 1 2 4 7), MOVE_DY ($9C23)
   from $AB81 (±16, ±1) or $ABCE (−15 −8 −4 −1 … 1 4 8 15). A held key
   moves once per tick, since the Apple repeats keys faster than the 4‑7
   ticks per second.
5. LIMIT_MOVE ($ACF8, X = Y = $FF: no limit), then for the player (CURRENT_OBJECT
   = 0): STOP_AT_WALLS ($AD40) unless WALLS_ON ($9C30) is 0, KEEP_ON_SCREEN
   ($A934), MOVE_OBJECT ($9DB3).

Right after it the levels call PLAYER_WALK_SPRITE ($DFA3; v1.0 $DFA4): the
larger part of the move picks two frames (up 0/1, down 2/3, right 4/5,
left 6/7, from PLAYER_SPRITES $BF30) and each tick toggles the step
(WALK_FRAME $8ED7) into sprite 0; GRAB_BUTTON ($BEBC): GRAB_STATE ($8E3E) 0
without a button (or both), 1 on a new press, unchanged while held (the grab
code advances it); KEEP_MOVE ($FE18): the move to $8E88/$8E89. Then the
world's own key commands read LAST_KEY (Level 1, $0963: `?` and `/` a hint,
Esc "quit?", `L` with some objects held, …). A message waits for a key inside
the tick ($0A77 polls $C000). Leaving a world goes through its only
`JMP ($03F2)` to the loader, with the request in $02D0 (1 the menu, 2 the next
level, 4 save the game, 5 …) and a level in $02D1.

**Object motion** (engine main, used by the player's input, the robots and
the worlds' code). Positions: x 0‑$85 (7 per tile), y 0‑$B0 from the bottom
(16 per tile), 20 × 12 tiles; an object is a 7 × 16 box.

* MOVE_OBJECT ($9DB3; MOVE_OBJECT_XY $9DB9 with X = room, Y = object): adds
  the move; x of $D8 and more has left by the left edge (+$86, ROOM_LEFT),
  $86 and more by the right one (−$86, ROOM_RIGHT); y likewise with $B1
  (ROOM_DOWN, ROOM_UP). The room it ends in → DESTINATION_ROOM ($9C2E), then
  SET_OBJECT_ROOM ($9E07): out of the old room's object list, into the new
  one's, which stays sorted by object number.
* KEEP_ON_SCREEN ($A934): a move past the left/right edge goes exactly to it
  ($FF/$86, SCREEN_EDGES_X $A979) and loses its vertical part; past the
  bottom/top ($FF/$B1) its horizontal part.
* STOP_AT_WALLS ($AD40): TEST_MOVE ($AE69) checks the box's four corners
  after the move: bit 0 a wall (WALL_AT $B40B on the room's bitmap,
  ROOM_WALLS_POINTER $9D56: 30 bytes, three bands of four rows from the top,
  a byte = two tile columns of 4 bits), bit 1 x ≥ $8C, bit 2 y ≥ $C0. On a
  wall only, it keeps the longer part of the move and stops the shorter one
  at the edge of the tile the object is in (STOP_AT_TILE_ROW $AE2A /
  COLUMN $ADD5), then the other way round, else stops both. Bit 1 clears the
  vertical move, bit 2 the horizontal one.
* LIMIT_MOVE ($ACF8): at most X across, Y up or down (the worlds' code uses
  it for other objects).

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
L1_MAIN_LOOP and the cycle counter.) `GameLoop` on the worlds built from the
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
  $C030, and the input devices (`InputDevices`): buttons $C061/$C062, paddle
  timers $C064/$C065 started by $C070 and timed by the CPU's cycle counter
  (2816 cycles at position 255, as AppleWin). Without a joystick (the
  default) the timers never run out, so the engine finds none and plays by
  keyboard; a joystick can be plugged in at any time. (Timers that run out
  at once read as a joystick held up‑left: the player walks off.)
* **native routines**: a Swift method of `Engine` registered at an engine
  entry point runs when the 6502 code reaches it – by JSR, JMP or falling
  through (CPU traps) – and returns like RTS. It works on the same memory
  (`m`, a `RAM`: the CPU's own bytes with every symbol of `GameSymbols` by
  name), the registers (`r`) and the input devices, takes its parameters
  where the 6502 code does and must leave memory **byte for byte** as the
  original leaves it, temporaries included, and A, X, Y and the flags where
  other code may use them (routines that the worlds' code calls). It may
  decline a case it doesn't handle (READ_INPUT with a mouse) and the
  original code runs. Each native names the routine it replaces and the
  ones it reproduces besides (`Native.all`); every one of them has its code
  ranges and their MD5 per engine build and version in `GameSymbols`. The
  loader (`WorldBuilder`) checks them when it loads a world (`CodeCheck`),
  and `GameScreen` installs only the natives whose routines all match: a
  modified routine, or an unknown version, runs as the original code
  (Symbols.md).

So level and room code always runs as the original code, and engine
routines become Swift one at a time. Ported so far (methods of `Engine`):

| Routines | File | Worlds |
|---|---|---|
| DRAW_ROBOTS $D2BC, DRAW_ROBOT_INTERIOR $D72B (kit/lab $D2AB/$D674), with DRAW_SPRITE(_COLOUR), PLOT, the lines and DRAW_BOX (Robots.md) | `RobotDrawing`, `EngineGraphics` | all |
| READ_INPUT $A90C | `PlayerInput` | all |
| MOVE_OBJECT $9DB3, MOVE_OBJECT_XY $9DB9, SET_OBJECT_ROOM $9E07, ROOM_WALLS_POINTER $9D56, WALL_AT $B40B, STOP_AT_WALLS $AD40, KEEP_ON_SCREEN $A934, LIMIT_MOVE $ACF8 (registers exact) | `ObjectMotion` | all |
| PLAYER_WALK_SPRITE $DFA3 (v1.0 $DFA4), GRAB_BUTTON $BEBC, KEEP_MOVE $FE18 | `PlayerInput` | levels |
| PLAY_SOUNDS $9F3C with PLAY_TONE $9EBB, PLAY_NOISE $9E7A (registers, cycles and clicks exact; Sound.md) | `Speaker` | all |

A native routine takes no CPU cycles unless it reports them
(`Engine.elapsed`, added to the CPU's when it returns). PLAY_SOUNDS does, to
the cycle, as a sound stops the game for up to 2 s; the others don't yet, so a
tick with natives is shorter than the original's (READ_INPUT's paddle loop
alone is about 3,000 cycles): the tick's work is identical, but the
*Authentic* pacing runs a little fast where natives run. To be fixed by
giving natives the original's cycle count.

`GameScreen` uses this for the viewer: it runs the world's start‑up code
($0803 up to the main loop) once, then for any room sets $9C2D and runs the
draw phase, so rooms look exactly as in the game, including what the world's
own code draws. A world built from the disks starts with the random generator
at $4E/$4F = 0, which it never leaves; `GameScreen` seeds it (Robots.md).

`GameLoop` runs the main loop from there as in the game, with the input
devices (`devices`; the viewer's *Play* types keys): it is run by CPU cycles and the page on screen ($C054/$C055) is what the
Apple shows, so each tick takes as long as its work. To watch any room, the
selected room replaces the player's in `CURRENT_ROOM` when the loop arrives at
the draw phase, and the loop's own value goes back before the page flip, so
the rest of the tick (including the `$6300 ↔ CURRENT_ROOM` swap around $9F3C)
sees what the game would. Watching the player's room changes nothing
(checked tick by tick on every world); elsewhere only what the draw phase
writes differs. A room change shows the room at once, drawn on a copy of the
machine at the start of the tick (`preview`). All eleven worlds (nine from
the v1.1 disks, two saved games) run 100 ticks with the player standing
still; v1.0 needs its own file lengths (`GameCatalog.lengthsV10`: its
level engine is one byte longer, and that byte is code). The loop stops
where the world hands back to the loader (`exit`, its `JMP ($03F2)`): the
menu, the next level, saving – the loader is not emulated yet.

## Porting strategy

1. **Reference engine** – the original code on `CPU6502` in `Machine`, with
   the language‑card banking and the input devices (done: whole ticks in
   `GameLoop`). This gives golden traces: the world memory after every tick
   for a given input sequence.
2. **Native engine** – port the engine routine by routine as native routines
   of the hybrid engine (above): input, player movement, grabbing, linked
   objects, robots (thrusters, bumpers, antennas, grabbers, sensors,
   batteries), wires, gates, chips, room transitions. Done: the robot
   drawing, the input and the object motion. Each starts with its symbols:
   its variables, tables and code (with fingerprints) in `GameSymbols`
   ("Mapping a new routine" in Symbols.md).
3. **Lock‑step tests** – `Data/native_check.sh` compares every native routine
   with the original, per call on random states, per drawn frame and over
   whole ticks (each world's main loop, 40 ticks: all memory, bank 1 and the
   page on screen after every tick), and 300 more ticks with the same input
   fed to both before every tick (keys held for a while, then a joystick
   and its buttons); any difference points to the routine to fix.
4. **Level and room code** ($0803 code, $8EF0 segments, code rooms) stays
   original 6502 code: it is world‑specific puzzle logic that pokes the same
   tables, and running it as is cannot break it.
