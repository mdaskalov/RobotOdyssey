# Robot Odyssey I (Apple II) – World Format

A world is the memory image **$6000‑$94FF** (53 pages). Every world – level,
tutorial, lab or saved game – has the same layout. Tables are
*structure of arrays*: one 256‑byte (objects), 64‑byte (rooms) or 128‑byte
(texts) array per field.

```
$6000 objects     10 arrays x 256        $7880 texts       8 arrays x 128
$6A00 sprites     64 x 16 bytes          $7C80 text strings
$6E00 rooms       8 arrays x 64          $8200 robots, chips, circuit tables
$7000 room walls  64 x 30 bytes          $861C wires       5 arrays x 256
$7780 ? (256 bytes, sprite-like)         $8EF0 level-specific code/data
```

## Coordinates

Objects and texts use **x = 0…139** (one unit = 2 screen pixels = one colour
pixel) and **y = 0…191 counted from the bottom**: screen line = 191 − y.
The room is 20 × 12 tiles of 7 × 16 units (14 × 16 screen pixels).
An object moving past x ≥ $86 or y ≥ $B1 (or below 0) enters the linked room
and wraps (engine $9DB3).

## Objects ($6000‑$69FF)

| Array | Field | Notes |
|---|---|---|
| $6000 | next | next object in the same room ($FF end; $FE seen on the player) |
| $6100 | sprite | 0‑63 |
| $6200 | colour | 0‑7 (see colours); for wires/pins the colour *is* the signal: orange (5) = on |
| $6300 | room | 0‑63; **$3F = nowhere** (not in the world) |
| $6400 | x | |
| $6500 | y | |
| $6600 | link | object this one follows ($FF none) – multi‑sprite objects, carried things |
| $6700 | dx | signed offset from the link object |
| $6800 | dy | |
| $6900 | flags | $00/$FF |

Object 0 is the player (sprite 0), $FE is linked to it: the tip of the
tool in hand (blank but for the soldering pen's). $FD is the soldering pen,
$FC the remote control (Engine.md, TAKE_TOOL). Robots are pairs of
objects (sprites $2A/$2B, left/right half); the robot table at **$8200** lists
the body object of each of the 4 robots (`$8200‑$8203`, Level 1: F0 F2 F4 01)
and its interior room (`$8204‑$8207`: 09 0A 0B 0D).

## Sprites ($6A00‑$6DFF)

64 sprites × 16 bytes. Byte *r* is row *r* counted **from the bottom**; bits
6…0 are the 7 pixels **left to right** (bit 6 = leftmost). Each pixel is 2
screen pixels wide.

The engine has 7 pre‑shifted draw routines (table at $AF4C, one per
`(2x) mod 7`). Every row with pixels rewrites *all* bytes it spans – 2 bytes
for shift 0, 3 otherwise – with mask = pixel bits | $80, i.e. the covered
pixels take the colour pattern and those bytes take the pattern's palette bit.
Shift 0 also sets the palette bit of the third byte if it is empty.

## Rooms ($6E00‑$6FFF, walls at $7000)

| Array | Field |
|---|---|
| $6E00 | first object in the room ($FF none) |
| $6E40 | floor colour (index into the colour table, usually $04 black) |
| $6E80 | wall colour |
| $6EC0 | room above |
| $6F00 | room below |
| $6F40 | room to the right |
| $6F80 | room to the left |
| $6FC0 | (unused, zero) |

A link to the room itself means no exit.

**Walls**: 30 bytes per room at $7000 + 30·room = 3 bands of 4 tile rows;
in a band, byte *c/2* holds two columns (low nibble = even column), and bit *k*
of a nibble is row *k* of the band (bit 0 = top). So `1F 11 … 11 F1 | 0F 00 … F0
| 8F 88 … 88 F8` is a closed box.

**Code in unused rooms.** Unused rooms link to themselves on all four sides,
and some worlds keep 6502 code in their wall bytes. Level 5 rooms $16‑$1D
(wall colour 6, $7294‑$7376) hold a routine the main loop calls every tick
(`JSR $7294` at $08DA): once $8F96 is set ($1060, buttons pressed in order
in the transporter room $2A) it draws the active transporter, and when the
player stands on it at (70, 20) it runs its own redraw loop that beams the
player out and leaves through the ESC wait at $09C1 to `LDY #5 / JMP $097B`.
The Lab ($7400, rooms $22‑$39) and Lab Tutorial ($774E, rooms $3E‑$3F) do
the same. Level 5's texts 31‑33 in these rooms are empty strings.

`World.code_rooms` (Python) and `World.findCodeRooms` (Swift) find such rooms:
a JSR/JMP in the world's code ($0803‑$1FFF, $8EF0‑$94FF) into the wall table,
followed through branches and JSR/JMP until RTS/RTI/JMP, must hit only valid
opcodes (no BRK), and every room it covers must link only to itself. The JSON
marks them with `"code": {caller, entry}`; the viewer shows them as code rooms.
Saved games lack the code below $0B00 and take the code rooms of the matching
level when those bytes are unchanged.

## Texts ($7880‑$7C7F, strings from $7C80)

| Array | Field |
|---|---|
| $7880 | room ($3F unused) |
| $7900 | x (style 0: drawn at byte column 2x/7) |
| $7980 | y of the first line's bottom row |
| $7A00 | style: 0 normal, 2 big (double height, coloured) |
| $7A80 | unused |
| $7B00 | colour (style 2) |
| $7B80/$7C00 | pointer lo/hi to the string |

Strings are high‑bit ASCII ending with $00; $8D (or any byte < $A0) starts a
new line 9 units lower (18 for big text); $A0 is a space.

## Wires ($861C‑$8B1B)

For each object *o* in the room's list with `$861C[o] ≠ 0` (the object at
the other end) a wire is drawn in *o*'s colour between
A = (`$871C[o]`, `$891C[o]`) and B = (`$881C[o]`, `$8A1C[o]`).
Objects $D1‑$DF in the room with `$8A82[o] ≠ 0` are loose wires with
A = (`$8A91[o]`, `$8AAF[o]`), B = (`$8AA0[o]`, `$8ABE[o]`).

These addresses are the levels'. The other worlds bring their own engine
pieces, which keep the same tables (same offsets from the `to` array) in the
world's code segment, and their $8200‑$8B1B is something else (Robot
Anatomy's text strings run from $7C80 through it):

| Worlds | Engine pieces (side B) | Wire tables | Drawn by |
|---|---|---|---|
| Levels 1‑5 | 247, 266, 274, 290 (side A) | $861C | $FC62 |
| Robot Anatomy, Toolkit | 360→$B900, 367→$D000, 383→$F000 | $14C0 | $FAAE |
| Innovation Lab, Lab Tutorial | 189→$B8E0, 196→$D000, 212→$F000 | $0B00 | $FB1E |

The robot state moves as well: grabbers and robot blocks at $8DBD/$8DCD in
the levels, $1ADF/$1AEB in Anatomy/Toolkit, $129F/$12AB in the lab worlds
(Robots.md).

Wires are **L‑shaped**, never diagonal ($FC62):

1. horizontal at **A's y** from ax to bx ($A04C) – x clamped to 0…$8A,
   skipped if ay ≥ $C0;
2. vertical at **B's x** from ay to by ($9FC4) – y clamped to 0…$BF.

So the corner is always at (bx, ay). Quirk: if the horizontal part is shorter
than 4 units, its pixel loop leaves the x variable at max(ax, bx)+1 and the
vertical part is drawn there, one unit right of bx. Pixels use the engine's
own (colour, shift) AND/OR tables at $A181/$A1C1/$A201/$A241, which OR the
palette bit; long horizontals are filled byte‑wise with masks $A135/$A12E and
patterns $A13C/$A144.

The engine propagates signals by copying colours along wires ($F0CC): a wire
or pin that carries current is orange.

## Colours (engine tables $9B91, $9BB1, $9BD1, $9BF1)

Each colour index has 4 pattern bytes. Sprites use bytes 0/1 for even/odd
screen byte columns; room tiles use byte `b mod 4` on even lines and
`(b+2) mod 4` on odd lines (a dither). Colour $14 (`F0`) means “don't draw”.

| # | Bytes | Colour |
|---|---|---|
| 0 | 00 00 00 00 | black |
| 1 | 2A 55 2A 55 | green |
| 2 | 55 2A 55 2A | purple |
| 3 | 7F 7F 7F 7F | white |
| 4 | 80 80 80 80 | black (palette 1) |
| 5 | AA D5 AA D5 | orange |
| 6 | D5 AA D5 AA | blue |
| 7 | FF FF FF FF | white (palette 1) |
| 8‑$13 | | dithered wall patterns ($0D = blue bricks) |

## Font

Engine $9500‑$97FF: 8 planes of 96 bytes; row *r* (0 = bottom) of character
*c* ($A0‑$FF) is at $9460 + r·$60 + c. Bit 0 is the leftmost pixel and every
bit is one screen pixel (text is not double‑width). Normal text is ORed into
the screen; big text is bit‑reversed into 16‑row sprites.

## Drawing order (one tick)

1. tiles (floor/wall patterns) – $9D03
2. texts – $A2A2
3. objects, following the room's list from $6E00 until $FF (no room check,
   max 255) – $9D18
4. wires, then loose wires $D1‑$DF – $FC62

`Data/ro_verify.py` runs these original routines on the 6502 emulator for
every room of the save state and compares with `Data/ro_render.py`: all 64
rooms are identical byte for byte. `RoomRenderer.swift` produces the same
bytes as the Python renderer for all 1152 rooms of v1.0 and v1.1.

**The rest of a frame.** A main‑loop tick draws more than these four steps:
robot exteriors and interiors ($D2BC/$D72B, see Robots.md), sprites drawn by
the world's own code (e.g. Robot Anatomy's $09CD with its table at $09BB: the
INPUT pin in room $1A, the OUTPUT pin in $1B, the lock in $06; Level 5's
transporter in its code rooms) and the remote control. The viewer draws all
of it by running the world's draw phase on the emulator (Engine.md);
`RoomRenderer`, its fallback for code rooms, draws only the four steps above.
