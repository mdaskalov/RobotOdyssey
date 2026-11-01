# Robot Odyssey I (Apple II) – Robot Drawing

Every tick, right after the room's objects ($9D18), the main loop calls two
engine routines that draw what the object table alone does not show:

| Build | Exteriors | Interior | Worlds |
|---|---|---|---|
| levels (side A, v1.0 and v1.1) | $D2BC | $D72B | Levels 1‑5, saved games |
| kit (side B) | $D2AB | $D674 | Robot Anatomy, Toolkit |
| lab (side B) | $D2AB | $D674 | Innovation Lab, Lab Tutorial |

The three builds run the same code with the variables, tables and sprites at
other addresses (levels `$8Exx/$83xx/$85xx`, kit `$1Bxx/$1Dxx/$1Exx`, lab
`$13xx/$15xx/$6Cxx`). The kit and lab builds have no robot 3. Apart from the
addresses there are three differences: they call the common part with
`JSR + RTS` instead of a tail `JMP`, they set up the blank sprite inline, and
they do **not** reset the rainbow step ($8E9B) before drawing robot 0.
v1.0 differs from v1.1 only in `JSR $9CC3 / RTS` → `JMP $9CC3` at the end of
the interior code (one byte, everything after it moves).

Native port: `RobotOddyssey/Engine/RobotDrawing.swift`, the same code for
all three builds; their addresses are in `GameSymbols` (Symbols.md), and the
port replaces the 6502 code only where the code's MD5 is the build's and
version's.

## Robots

Robot *i* is fixed in the code of every build:

| Robot | Body object | Interior room | Inside colour | Antenna colour from | Antenna signal when |
|---|---|---|---|---|---|
| 0 | $F0 | $09 | 7 white | object $66 | battery ≠ 0 and object $59 orange |
| 1 | $F2 | $0A | 6 blue | object $E6 | battery ≠ 0 and object $E5 orange |
| 2 | $F4 | $0B | 7 | object $E3 | battery ≠ 0 and object $E2 orange |
| 3 | $01 | $0D | 7 | object $0C | battery ≠ 0 and object $0B orange |

(The table at $8200 lists the same bodies and rooms, but these routines don't
read it.)

State per robot (levels addresses):

| Address | Contents |
|---|---|
| $8DBD + 4i | 4 grabbers (corners): 0 none, 1‑4 which of 4 grabber sprites |
| $8DCD + $1A·i | robot block: +$00‑$0B object numbers (Level 1 robot 0: F0 F0 F1 F1 51‑58) |
| … +$0C | 4 thrusters (up, right, down, left): 0 off, 1/2/3 flame frame |
| … +$10 | 4 bumper colours (bottom, left, top, right) |
| … +$18 | battery charge ($0F full) |
| … +$19 | switch (1 = on) |

## Exteriors ($D2BC)

For robots 0, 1, 2, 3 in this order, each only if its body is in the current
room ($9C2D). x and y are the body's position ($8EBF/$8EC0).

* **Robot 0** ($D44D): two black blanks ($84D4) at (x+1, y+3) and
  (x+5, y+3), then the *rainbow window* ($D6AB): the window sprite $8534
  plotted pixel by pixel ($A14D) from (x+2, y), each set pixel in the next of
  colours 4‑7 ($8E9A, which also advances once per bit). The step $8E9B is 1
  (reset to 0 and incremented by the routine; the kit and lab builds only
  increment it until it is 1).
* **Robot 1** ($D359): a blank at (x+3, y+3), sparks alternating between
  $8514 and $8524 every tick ($8E99), and two dots ($84C4, blue then orange)
  at random positions x + $8329[rnd 3], y + $832C[rnd 5].
* **Robot 2** ($D2C8): a black 10×2 bar ($A281) at (x+1, y+7) with an orange
  dot running along it: x + $831B[$8E98], $8E98 counting 13…0 and wrapping.
* **Robot 3** ($D4CC, levels only): a blank at (x+3, y+3) and three nested
  squares ($84E4/$84F4/$8504) at (x+2, y+3) whose colours rotate (phase $8E9E,
  colours $8334 + $8331[phase]).

Then the common part ($D573) for that robot, from copies of its state:

* **bumpers** – lines in the bumper colours: bottom at y−2 and top at y+18
  from x+3 to x+8 ($A04C), left at x−2 and right at x+13 from y+3 to y+12
  ($9FC4);
* **thrusters** – orange flames for the non‑zero thrusters, sprite from
  $836D/$8371 (value 1), $8375/$8379 (2) or $837D/$8381 (3+), at
  x + $8385[k], y + $8389[k];
* **grabbers** – white sprites $6DC0/$6DD0/$6DE0/$6DB0 (value 1/2/3/other) at
  x + $82D7[k], y + $82DB[k];
* **antenna** – $8544 at (x, y+16) in the antenna object's colour, plus the
  signal $8554 in white when it transmits.

### The random number generator

$D429 runs 8 steps of a 16‑bit shift register in $4E/$4F (feedback = bit 5
XOR bit 6 of $4F into bit 0 of $4E) and returns $4F. $D414 reduces it below
n by subtraction. Robot 1 draws two dots per tick, so **every tick in which
robot 1 is on screen advances the generator by 32 steps**, which matters for
everything else that uses it. The generator never leaves 0; the monitor's
keyboard wait leaves it non‑zero on a real Apple, but a world built from the
disks starts with 0, so `GameScreen` seeds it (Level 4's code loops until it
gets a usable number).

## Interior ($D72B)

When the current room is robot *i*'s interior:

* battery ($D783): frame $6C00 at ($15, $21), cells $6BE0 at ($0E, $21), both
  white, and an orange bar of charge+1 rows ($0C each) built in the 16‑byte
  sprite $8EC4 and drawn at ($0E, $21) (nothing when the charge is 0);
* 10 parts ($D7D0) in the robot's colour: sprite $833D/$8347[k] at
  ($8351[k], $835B[k]);
* the window $8534 at ($76, $8E) in white – standing under it ($DD59: player
  at x ≥ $74, y ≥ $8C) shows the room outside;
* the switch at ($76, $21): $6D00 orange when on, $6D10 white when off
  (toggled by $DD59 when the player is below y = $26 and GRAB_STATE $8E3E
  is 1).

## Drawing primitives used

| Routine | Parameters | Leaves |
|---|---|---|
| $9CC3 DRAW_SPRITE_COLOUR | sprite ($0D), x $18, y $14, colour X | $0F/$10 patterns, then $AF1F |
| $AF1F DRAW_SPRITE | | $AEE7‑$AEEA, $11‑$13, $15, $19/$1A |
| $A14D PLOT | colour A, x $18, y $14 | $A14C, $11/$12 |
| $A04C HORIZONTAL_LINE | colour $9C34, x1/x2 $9C35/$9C37, y $14 | $A044‑$A04B, $11/$12; under 4 units long it plots pixels and leaves $18 = max+1 |
| $9FC4 VERTICAL_LINE | colour $9C34, y1/y2 $9C36/$9C38, x $18 | $9FC1‑$9FC3, $11/$12, $14 = max+1 |
| $A281 DRAW_BOX | $9C34‑$9C38 | two HORIZONTAL_LINEs, two VERTICAL_LINEs |

All draw on the page the line tables point to ($9839 low bytes, ($16) high
bytes, set by FLIP_PAGE) and none clips at the right edge of a line. The
native versions (`EngineGraphics.swift`) leave every one of these temporaries
too, and the robot code keeps the 6502's carry where it reaches memory
(`ADC` pairs without `CLC`, the `ROL` in $D6AB).

## Verification

`Data/native_check.sh` (see Data/README.md) compares the native routines with
the original code:

* **frames** – every room of every world (and saved game) is drawn by the
  world's own draw phase twice, with the native routines and as pure 6502
  code: all memory, bank 1 and the screen must match;
* **ticks** – each world's main loop runs 40 ticks as in the game
  (`GameLoop`, no input), with the native routines and as pure 6502 code:
  all memory, bank 1 and the page on screen must match after every tick;
* **calls** – the two routines are called directly on 300 random states per
  world (robots in the room at random positions, thrusters, bumpers,
  grabbers, battery, switch, antenna, counters, generator, interior rooms),
  4 ticks in a row: all memory must match except the dead stack.

Result on v1.1 (with the saved games of `Robots_s.dsk`): 670 frames, 440 ticks
and 26,400 calls identical; v1.0: 542 frames, 360 ticks and 21,600 calls
identical (2026‑11‑01, after the move to the symbol maps).
