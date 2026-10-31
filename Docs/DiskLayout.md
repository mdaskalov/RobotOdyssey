# Robot Odyssey I (Apple II) – Disk Layout

Covers the two‑sided program disk of **v1.0 and v1.1** (identical layout, v1.1 has
code fixes) and the storage diskette used for saved games.
v2.0 (three sides) is different; see the end.

| File | Version | Side | MD5 |
|---|---|---|---|
| Ro1v11a.dsk | 1.1 | A | 46f60717423e1e3fef68f18fc7229b87 |
| Ro1v11b.dsk | 1.1 | B | 3ade4e78583155e49bd0d08b8c0adf5e |
| Ro1v10a.dsk | 1.0 | A | 0080e4fc5d65afc7ba39854584aa7b0c |
| Ro1v10b.dsk | 1.0 | B | fd5a8ca79eb416803e62116af11d71d7 |
| ROBOT-1/2.DSK, RobotOdyssey1/2.dsk, Robots_1/2.dsk | 1.0 | A/B | other cracks of v1.0, same data |
| Ro1v20a/b/c.dsk | 2.0 | A/B/C | other layout |
| DATAV10/11/20.DSK | – | storage | blank storage diskettes |

The other files in the disk folder: `level1.bin` is a 48K RAM dump
($0000‑$BFFF) taken while playing Level 1 (probably v1.0), `mike.bin` is its
first 8K, `6000.bin` a 24K dump of the same session. `RO_L1_SaveState.yaml` is a
Mariani/AppleWin save state of Level 1, room $28, with full 64K main + aux RAM.

## No DOS – the game's own loader

There is no DOS 3.3 catalog. Track 0 sector 0 is a normal DOS boot1 that loads
T0 sectors 1‑15 to $4F00‑$5DFF (boot stage 2 = a relocated DOS RWTS, entry
$5D00). Stage 2 reads track 1 to $4000‑$4EFF, runs a nibble copy‑protection
check (`D5 E7 E7 E7` + signature on track 1, also at $6255 in the menu) and
starts the **loader/menu program** at $4000.

The RWTS uses a custom sector skew (table at $5CB8):
`logical → physical = 0 3 5 7 9 B D F 2 4 6 8 A C E 1`.
In a DOS‑ordered `.dsk` image this means the k‑th page of a track is
`.dsk` sector:

```
k:      0 1 2 3 4 5 6 7 8 9 A B C D E F
sector: 0 6 5 4 3 2 1 F E D C B A 9 8 7
```

All addresses on disk below are **pages** = `track*16 + k` in this order
(`Data/ro_disk.py`, `DiskImage.page(_:)` in Swift). Files are runs of
consecutive pages; a file may start anywhere in a track.

## Loader file table (track 1, v1.1)

The loader routine at **$4A20** is called as `JSR $4A20` followed by inline
bytes `count, command (1=read, 2=write), pointer...`; each pointer leads to a
6‑byte entry `track, sector, addr lo, addr hi, bytes in last page, full pages`.
Length = pages × 256 + last. Entries live at $4D5E‑$4EE9.

Shared pieces (“engine”):

| Page | Load | Length | Contents |
|---|---|---|---|
| 64 | $0803 | 5p+208 | menu program (title screen, menu) |
| 70 | $6000 | 2p+248 | menu program, part 2 |
| 73 | $2000/$6300 | 55p+30 | title pictures (address patched at run time) |
| 129 | $9500 | 35p+215 | **engine main**: font $9500, colour tables $9B91, drawing, text… (identical on both sides) |
| 247 (A) | $1A50 | 5p+164 | engine piece (levels) |
| 253 (A) | $8200 | 12p+217 | robot/circuit tables for Level 1 |
| 266 (A) | $B8E0 | 7p+32 | engine piece (levels) |
| 274 (A) | $D000 | 15p+254 | engine, language card bank 2 |
| 290 (A) | $F000 | 15p+244 | engine, language card |
| 189/196/212 (B) | $B8E0/$D000/$F000 | | engine pieces for the lab worlds |
| 348/360/367/383 (B) | $14C0/$B900/$D000/$F000 | | engine pieces for Robot Anatomy / Toolkit |

Worlds (menu dispatch at $4040; level loads at $4582‑$460E, next‑level loads
at $40B9‑$40DD):

| World | Side | Segments (page → address, length) |
|---|---|---|
| Level 1 – City Sewer | A | 306→$6000 34p · 253→$8200 12p+217 · 357→$8EF0 5p+2 · code 340→$0803 16p+223 |
| Level 2 – Subway | A | 363→$6E40 19p+192 · 400→$8EF0 1p+63 · code 383→$0803 16p+103 |
| Level 3 – Town | A | 402→$6E40 19p+192 · 441→$8EF0 5p+249 · code 422→$0803 18p+44 |
| Level 4 – Master Computer Center | A | 447→$6E40 19p+192 · 484→$8EF0 5p+97 · code 467→$0803 16p+98 |
| Level 5 – Skyways | A | 490→$6E40 19p+192 · 529→$8EF0 5p+217 · code 510→$0803 18p+42 |
| Innovation Lab | B | 228→$6000 53p · code 281→$0803, 168→$0B00 |
| Robot Anatomy | B | 396→$6000 53p · code 449→$0803, 348/454→$14C0 |
| Toolkit | B | 461→$6000 53p · code 514→$0803, 348/524→$14C0 |
| Innovation Lab Tutorial | B | 284→$6000 53p · code 337→$0803, 168/340→$0B00 |

Leftover fragments of the original assembler source on the disk (side A page
128) name these files `KITPREASM1..4`, `TUT3WORLD`, `LABPREASM2`, `FONTADV`, …

**Levels 2‑5 only load rooms, walls and text** ($6E40‑$81FF) plus their code.
The object table ($6000‑$6E3F, including what the player and robots carry) is
inherited from the previous level. When the player leaves a level, the level
code runs an *exit script* that moves objects into the next level’s rooms and
parks the rest in room $3F (“nowhere”), then sets `$02D0=2` (next level),
`$02D1=n` and restarts the loader:

| Exit script | v1.1 | v1.0 |
|---|---|---|
| Level 1 → 2 (table of 6 objects) | $0B93 | $0B93 |
| Level 2 → 3 (16 objects) | $0B76 | $0B6F |
| Level 3 → 4 (in the $8EF0 segment) | $93BD | $93BC |
| Level 4 → 5 (parks everything not carried, brings in 33 objects) | $0AFC | $0AFC |

The viewer/extractor rebuild levels 2‑5 by running these scripts on a 6502
emulator, so they show the state of a level entered from an untouched
previous level. The entries are found in the code
(`ro_world.find_exit_entry`, `WorldBuilder.exitEntry`): the exit code ends
with the only `LDY #next / JMP handler` (handler = `LDA #$02 / STA $02D0`),
and its entry is the lowest JMP/JSR target before it from which straight‑line
code runs into that `LDY`.

## Storage diskette (saved games)

Boot sector starts `01 A6 2B BD 88 C0` (prints “insert program diskette”).
Page 32 is the directory: 16‑byte names (high‑bit ASCII), e.g. `Level 1 mike`.
Slot *k* (0‑3) occupies 107 pages from page **117 + 107k**:

| Pages | Memory | Contents |
|---|---|---|
| +0 | $5E00 | header: $40‑$43 = $9C26,$9C27,$A5C9,$A5CA; $44 = world index ($02D2) |
| +1…+32 | $D000‑$EFFF | language‑card RAM (bank 1 $D000‑$DFFF, then $E000‑$EFFF) |
| +33…+85 | $6000‑$94FF | the world |
| +86…+106 | $0B00‑$1FFF | level code and state |

Restoring loads these and then reloads the level code at $0803 selected by the
header’s world index (0‑4 = levels 1‑5, 5 = lab). In the sample disk the Level 2
save has index 0, so the viewer identifies a save’s level by comparing room
walls instead.

## Copy protection and the dumps

Track 1 holds a nibble pattern a `.dsk` cannot store (`D5 E7 E7 E7`, then
`FC EE EE FC E7 EE FC E7`), checked at boot ($5D58, result in bit 7 of $03FE)
and when the menu starts ($6255, result in $02CE). Starting a world sets
`$9C4E = $03FE AND $02CE`; the level code skips $F7BE/$F5C2 (Level 1 main loop
$08DA) when the flag is clear. Boot stage 2 also sets the reset vector
$03F2/$03F3 to $C600, which the game uses to return to its loader.

All the .dsk files are cracked, each differently (details and a ranking in
`README.md` next to the disk images): Ro1v11 and Ro1v10 turn the failure
path into success (`SEC`), Ro1v10 and RobotOdyssey also force $9C4E in the
loader, ROBOT‑1/2 (“(K) 1985 MR. CLEAN”) removes the retry loop, and
Robots_1/2 removes the reset vector and patches only some of the
`JMP ($03F2)` exits (levels 2‑5 are missed). Version fingerprints that the
cracks leave alone: MD5 of side A pages 383‑399 and side B pages 196‑211
(`GameCatalog.fingerprints`).

v1.1 is a bug‑fix release of v1.0: engine ($D000/$F000), loader, menu,
title pictures and level code changed; world data differs only on 3 pages of
Level 2, 1 of Level 4 and 1 of the Lab Tutorial.

## Version 2.0

Three sides; boot sector byte 2 is the side number (00/01/02). Worlds are
found by the text‑pointer signature at pages 280, 338+$C0, 409+$C0, 453+$C0
(side A), 257, 403, 461 (B), 225, 262, 310, 465, 515 (C). The engine's font is
at page 189 and the colour tables at page 180+$91, i.e. the engine is laid out
differently and the track‑1 loader is not the v1 one. Not yet supported.
