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
$9D18 DRAW_ROOM_OBJECTS   $101A (level)  $D2BC  $D72B ROBOT_INTERIOR_Q
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

## Porting strategy

1. **Reference engine** – run the original engine (from the user's disks) on
   the Swift `CPU6502`, headless, one tick at a time, with the
   language‑card banking used by `Data/ro_timing.py`. This gives golden
   traces: the world memory after every tick for a given input sequence.
2. **Native engine** – re‑implement the tick subsystem by subsystem in Swift
   (input, player movement, grabbing, linked objects, robots: thrusters,
   bumpers, antennas, grabbers, sensors, batteries; wires, gates, chips;
   room transitions; level scripts).
3. **Lock‑step tests** – feed the same input to both and compare the world
   ($6000‑$94FF, $D000‑$EFFF) after every tick; any difference points to the
   routine to fix. Rendering is already exact (RoomRenderer).
4. Level scripts ($0803 code, $8EF0 segments) can first run on the
   emulator inside the native engine and be ported one by one.
