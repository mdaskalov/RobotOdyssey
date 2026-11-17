# Robot Odyssey I (Apple II) – Copy Protection

The game never refuses to start. A disk that fails the check plays normally
until the player picks up the **soldering pen**: it can be carried, but it
solders nothing (no sound, no wire), and the robots can't be wired. The
check runs at boot and in the menu, the loader turns its result into a flag
when it starts a world, and the worlds' main loops test the flag.

The app passes both checks as an original disk does (see
[In the app](#in-the-app)). Until 2026‑11‑01 the flag kept its value from
the disk, $00, and the pen did nothing in *Play*.

This describes v1.0 and v1.1. v2.0 checks a different sector, and only in
the menu (see [Version 2.0](#version-20)).

## On the disk

Track 1, physical sector 1 (DOS order T01,S07; loader page 31, the one page
of track 1 the loader doesn't load). Its data field holds a run of `E7`
nibbles (data bytes `AC 00 AC 00 …`, e.g. at $A4‑$AF). On the original disk
the run is written with extra zero bits between the nibbles; Passport calls
this an *E7 bitstream*. After the check touches `$C08D,X` and waits
(`BIT $2D`), the drive's shift register picks up the bits in another
alignment and reads other nibbles: `EE`, then the signature. A `.dsk` image
keeps only the decoded bytes, so from an image the check reads `E7`s and
fails. (A `.dsk` can't show the extra bits; this follows from the check's
code and Passport's notes.)

## The check

The same code twice: inline in boot stage 2, and as a subroutine in the menu
program (result in the carry).

```
        seek track 1 (RWTS, IOB $59E8)
        up to 10 tries ($09), each up to 128 address fields ($08):
          wait for the address field of sector 1 ($5644; $2D = sector)
          wait for D5 (at most 256 nibbles), then E7 (at most 256), E7, E7
          LDA $C08D,X / BIT $2D          the bit slip
          wait for EE (at most 16 nibbles)
          8 nibbles = SIGNATURE+7, +6 … +0   last byte first
          → SEC (passed)
        all tries failed → CLC
```

The signature is `FC EE EE FC E7 EE FC E7`, compared from its last byte, so
on the disk it reads `E7 FC EE E7 FC EE EE FC`.

| Check | Code | Signature | Result |
|---|---|---|---|
| boot (BOOT_COPY_CHECK) | $5D58‑$5DD5, failure `CLC` at $5DD2 | $5DDC | `ROR $03FE` at $5DD6: bit 7 of BOOT_CHECK_RESULT |
| menu (MENU_COPY_CHECK) | $6255‑$62EF, failure `CLC` at $62EB; called from $6011 and $6028 | $62F0 | `ROR $02CE` at $6014/$602B: bit 7 of MENU_CHECK_RESULT |

## The flag

COPY_PROTECTION_OK ($9C4E, in engine main) is $00 on the disk. Only the
loader writes it, and only bit 7 counts:

| Loader | When | Code |
|---|---|---|
| COPY_FLAG_START $4563 | starting a world (menu, next level) | `LDA $03FE / AND $02CE / STA $9C4E` |
| COPY_FLAG_RESTORE $452D | restoring a saved game | the same, then RESTORE_LOAD_CODE |
| RETURN_TO_WORLD $434D | back to the world after saving | `ASL $03FE / ROR $9C4E`, then RESTORE_LOAD_CODE |

Every return to the loader is a boot, and every boot shifts its result into
bit 7 of $03FE (`ROR`), so the `ASL` after a save takes the latest boot's
result into the carry; the `ROR $9C4E` makes it the flag. (Until 2026‑11‑01
this was an open question here: the `ASL` leaves $03FE shifted, but the next
boot shifts it back in.)

## What it disables

Every world but Robot Anatomy (which has no pen) tests the flag once per
tick, in its main loop right before the wires are drawn:

```
        LDA TOOL_MODE          tool in hand, set by grabbing ($BE6D); $FD the pen
        CMP #$FD
        BNE draw
        EOR COPY_PROTECTION_OK $FD EOR $80 = $7D: go on; $FD EOR $00 = $FD: skip
        BMI draw
        JSR SOLDER_WIRE        starts a wire at the first touch (solder sound), makes it at the second
        JSR SOLDER_TOUCH       acts on what the pen touches while no wire is started
draw    JSR DRAW_WIRES
```

| World | Test (`EOR $9C4E`) | TOOL_MODE | Skipped calls |
|---|---|---|---|
| Level 1 | $08E1 | $8DAA | $F7BE SOLDER_WIRE, $F5C2 SOLDER_TOUCH |
| Level 2 | $08F1 (v1.0: $08EA) | $8DAA | the same |
| Level 3 | $0907 | $8DAA | the same |
| Level 4 | $090C | $8DAA | the same |
| Level 5 | $08F9 | $8DAA | the same |
| Toolkit | $08D5 | $1ACE | $F652, $F1AF |
| Innovation Lab Tutorial | $08CE | $128E | $F59B, $18B0 |
| Innovation Lab | $08C9 | $128E | $F59B, $18B0 |

The routines and the variable are 6502 code and data of the worlds and
engine, not native routines.

## The dumps

Every working image is cracked, since a `.dsk` can't hold the bitstream. They
differ only in how they get past the check (offsets below are memory
addresses; disk pages in DiskLayout.md):

| Disks | Version | Change | The check |
|---|---|---|---|
| Robot Odyssey v1.1 (4am crack) side A/B, the app's bundled `diskA.dsk`/`diskB.dsk` | 1.1 | Passport (2021): 12 data bytes of the E7 sector, $A4‑$AF `AC 00 …` → `78 A8 58 9C 30 C0 04 A8 58 9C 58 A8`; no code changed | passes on the first try |
| Ro1v11a/b | 1.1 | failure exits $5DD2 and $62EB `CLC` → `SEC` | fails 10 times, then counts as passed |
| Ro1v10a/b | 1.0 | the same, and the loader's $452D/$4563 → `LDA #$80 / AND #$80 / NOP / NOP` | as Ro1v11; flag forced |
| ROBOT‑1/2 (“(K) 1985 MR. CLEAN”) | 1.0 | `SEC` as Ro1v10, retry `DEC $09 / BNE` → 4 `NOP`s; a credit line at boot | fails once, counts as passed |
| RobotOdyssey1/2 | 1.0 | only the loader's flag forced, as Ro1v10 | fails 10 times each (slow); flag forced |
| Robots_1/2 | 1.0 | comparison branches bent; reset vector removed (breaks leaving levels 2‑5) | passes |

Passport's bytes make the plain nibble stream contain the signature, so the
original code finds it without the bit slip:

```
original   … E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 …
Passport   … E7 E7 CF F3 FC EE E7 FC EE E7 FC EE EE FC 97 …
                            ^^ EE, then E7 FC EE E7 FC EE EE FC
```

The 4am disks are byte for byte Ro1v11 apart from those 12 bytes and the two
`CLC`s (and an unused page 545 on side A), so they hold the original v1.1
code.

## Version 2.0

The woz-a-day `.woz` images of v2.0 (sides A, B and C) are the original
disks, bitstream included. The protection works as in v1.1, with three
differences: the E7 sector is somewhere else, there is no boot check, and
saving doesn't check again. The addresses below are v2.0's (side A, read
from memory after booting to the menu). The v1.1 addresses elsewhere in
this document don't apply.

**On the disk.** Track 7, physical sector 7, on all three sides. Its data
field is `D5 AA AD`, 246 × `96`, 96 × `E7`, `96` (checksum), `FF FF EB`. The
address field ends 26 nibbles before the `D5`. The first E7s have extra 0
bits after them. Their lengths in bits are
`9 9 8 8 10 8 9 10 8 9 10 8 9 9`, then 8 for the rest:

```
111001110 111001110 11100111 11100111 1110011100 ...
E7 0      E7 0      E7       E7       E7 00
```

When the shift register restarts 3‑7 bits after the third E7 (where the
check's `$C08D` puts it), it reads `FC E7 FC EE E7 FC EE E7 FC EE EE FC`:
an `EE`, then the signature.

**The check** (MENU_COPY_CHECK, $6205‑$629D, result in the carry):

```
$6205   slot × 16 → X ($03F3); motor on ($C089), read mode ($C08E)
$6215   seek track 7 (LDA #$07 / ASL / ASL $565A / JSR $5422)
$6223   ($13) → signature $629E;  $09 = 10 tries
$622F     $08 = 128 address fields
$6233     DEC $08 / BEQ next try
$6237     JSR $5698 (read address field) / BCS next try
$623C     LDA $566E / CMP #$07 / BNE        sector 7
$6243     wait for D5 (at most 256), then E7 (at most 256), E7, E7
$6271     LDA $C08D,X / BIT $2D             the bit slip
$6276     wait for EE (at most 16 nibbles)
$6284     8 nibbles = ($13),Y, Y = 7 … 0
$6292     SEC → $629A
$6295   next try: DEC $09 / BNE $622F
$6299   CLC
$629A   LDA $C088,X (motor off) / RTS
```

Signature at $629E: `FC EE EE FC E7 EE FC E7`, the same as v1.1. It is
called from $600B and $6020 (`JSR $6205 / ROR $02CE`), so bit 7 of
MENU_CHECK_RESULT ($02CE) is the result.

**No boot check.** Booting to the menu touches `$C08D` once, in the menu
check. The loader never reads $03FE, and after booting it stays $00.

**The flag** (COPY_PROTECTION_OK, $9C4E, as in v1.1):

| Code | What |
|---|---|
| $4557 | `LDA $02CE / STA $9C4E` |
| $45AF | `LDA $02CE / STA $9C4E` |
| $436F | `SEC / ROR $9C4E`: back to the world after saving; the flag is set, no check (v1.1: `ASL $03FE / ROR $9C4E`) |

So the menu check alone decides. Which of $4557/$45AF starts a world and
which restores a saved game wasn't traced. Neither were the worlds' flag
tests in v2.0, which are presumably as in v1.1.

**In emulators.** The `.woz` passes only if the emulator clears the shift
register on `$C08D` in read mode, then starts the next nibble at the next 1
bit under the head (AppleWin's `LoadWriteProtect`). An emulator that turns
the track's bits into nibbles once reads only E7s. The check then fails all
10 tries, the flag is $00, and the pen solders nothing. Mariani passes.
Apple2Kit passed only after it got bit slips (2026‑11‑17). Since then the
check passes on the first try.

## In the app

`WorldBuilder.passCopyProtection` sets COPY_PROTECTION_OK, BOOT_CHECK_RESULT
and MENU_CHECK_RESULT to $80 in every world it loads and every saved game,
as the loader leaves them when both checks pass (and as the Ro1v10 crack
forces the flag). When a world hands back to the loader, the app runs boot
stage 2, the loader and the menu as 6502 code (Loader.md); natives stand in
for the two checks: BOOT_COPY_CHECK goes on at $5DD3 with the carry set,
MENU_COPY_CHECK returns with it set, as the checks end on an original disk.
The original code then sets the flag. So every dump plays alike, the pen
included.

Checked with each level running 20 ticks with TOOL_MODE = $FD: SOLDER_WIRE
and SOLDER_TOUCH run on every tick with the flag at $80 and never at $00
(v1.0 and v1.1).
