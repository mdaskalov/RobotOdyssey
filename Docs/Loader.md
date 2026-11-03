# Robot Odyssey I (Apple II) – The Loader in the App

A world never loads another world itself. It hands back to the loader,
which loads the next level, shows the menu, saves and restores games and
chips (DiskLayout.md, *The loader's requests*). The app runs that part of the
game as original 6502 code, as it runs the worlds' code, so level changes,
the menu, saving and restoring behave as on the Apple, screens and prompts
included. Natives stand in only for hardware the app doesn't have: the boot
ROM, the disk drive and its nibbles.

## From a world to the loader and back

1. The world sets its request (MENU_MODE…) and jumps to `JMP ($03F2)`. The
   app's worlds have the reset vector set as boot stage 2 leaves it, $C600
   (`WorldBuilder.passCopyProtection`).
2. **Boot** (`Loader.boot`, a native at $C600, in place of the slot 6 boot
   ROM and DOS 3.3's boot stage 1): track 0 of the disk in the drive, sector
   0 to $0800 and sectors 1‑15 (DOS order) to $4F00‑$5DFF; the monitor's
   window, I/O hooks and cursor as boot 1's calls to SETKBD, SETVID and the
   end of SETTXT leave them (CHAR_OUT keeps to the window at $20‑$23); X =
   $60; on to BOOT2_ENTRY ($5D00). Boot 1 skips the ROM's display switches,
   so the screen stays as the world left it.
3. **Boot stage 2** runs as 6502 code: it points the reset vector at $C600,
   reads track 1 to $4000‑$4EFF through RWTS, runs the copy check and jumps to
   LOADER_START.
4. **The loader** (and the menu, when it loads it) runs as 6502 code, on the
   keyboard the viewer types to.
5. **START_WORLD** ($456C) jumps to WORLD_START ($0803): `GameLoop` sees the
   jump, tells the world by its code at $0803 (`Loader.world`: the catalog
   world whose code file is there), checks its engine as the loader's
   `CodeCheck` does (the world may be another engine build: levels, kit, lab)
   and lets its start‑up code run; when it arrives at its main loop, the
   natives its check allows go in and the ticks run on. The viewer selects
   that world in the sidebar and goes on with the game (`followLoader`).

While the loader runs (and while a world it started runs its start‑up code)
the canvas shows the page on screen, the *Current Room* panel's status the request
(“The loader: on to the next level…”), and the arrow keys are the Apple's
(← $88, → $95, ↑ $8B, ↓ $8A: the menu's cursor) instead of I J K M. The
speaker's clicks of the loader's own code (CHAR_OUT's bell, the menu's and
the intro's tunes) are streamed to the cycle as the loader runs
(`GameLoop.takeSpeaker`, `SpeakerStream`, Sound.md *The port*). Before
2026‑11‑03 they were played a sound at a time, from a click to a pause of
50,000 cycles: a tune was heard only once it had ended, the intro's
seconds after their pictures and its last (7 s) over Robotropolis; and
before 2026‑11‑01, in pieces of the viewer's steps, broken up and slowed
down.

## The natives (`Loader.install`)

| Address | Stands in for | Does |
|---|---|---|
| $C600 SLOT6_BOOT | boot ROM, boot stage 1 | as above |
| $5A00 RWTS | DOS 3.3's RWTS | the IOB at A:Y: seek (0), read (1), write (2) or format (4) on the drive's disk at once; the IOB's return code ($10 write‑protected, $40 drive error) and the carry as RWTS leaves them |
| $5D58 BOOT_COPY_CHECK | the nibble check at boot | goes on at BOOT_COPY_DONE ($5DD3) with the carry set: the check passed |
| $6255 MENU_COPY_CHECK | the menu's check | returns with the carry set |
| $4B85 AWAIT_SIDE | swapping disks | puts the disk WANTED_SIDE ($0E) asks for in the drive, then the original code runs: it reads the side and finds it |
| $4550 PLAY_INTRO | – | steps over START_CHOSEN_WORLD's `JSR $6000`: Robotropolis' intro (pictures, wipes and tunes in the menu's bytecode, 26 s) doesn't play; a key press ends it on the Apple too. The one with original code to fall back to: switched off in the *Current Room* panel (`Machine.switchedOff`, `Loader.skipIntro`), the intro plays – 7 tunes, 25,966 clicks in v1.1 |
| $0A71 DRAW_PICTURE | the menu interpreter's op 00 | the picture in Swift, at once (`Loader.menuNatives`, Engine/MenuDrawing.swift): the menu's frame, the title's five pictures (into the wipe's buffer), the intro's eight. On the Apple 0.07‑0.34 s each, while the intro's tunes wait |
| $0D21 XOR_BLOCK | op 06 | the block XORed onto page 1 at once: the menu's highlight, the intro's flashing between its short tunes (22 ms each on the Apple, two in a row) |

DRAW_PICTURE and XOR_BLOCK run where the routine's code is the menu's
(`Routine.code`, the same in v1.0 and v1.1): at those addresses a world has
code of its own (the hooks stay; the bytes last checked are kept, so a
world's code is hashed once). Like the engine's natives they leave memory as
the original (`loader_check`'s *menu natives*: each call against the
original run on a copy), take no time and have switches under *Loader*;
off, the original draws. With them the intro takes 24.0 s instead of 26.0:
its tunes no longer wait for the pictures (Sound.md). The wipe (op 01, 1.2 s
at the intro's start, its iris of circles) stays the original's: its time
is the effect.

The disks are what `DiskDrive` has: the program disk's two sides of the
world's version and one storage disk. The program disk is write‑protected,
as the originals are. Sectors are by track and the loader's sector number,
which is a page's place in its track (`DiskImage.page`; RWTS's skew table
$5CB8 and the .dsk's DOS order cancel out to it).

Where the loader asks for a disk and waits for Return (“Insert Robot
Odyssey STORAGE disk and press RETURN”), Return finds the disk asked for in
the drive. Where it needs the disk it has (the next level), it doesn't ask.
The one prompt that takes any disk – loading a chip from side 2's library or
a storage disk – reads the disk in the drive: the *Current Room* panel's *Drive* puts
another in.

## The storage disk

The drive gets the loaded storage disk named `save.dsk`, else the first
storage disk loaded. Without one it makes a blank `save.dsk` (as the
loader's NEW_STORAGE_DISK would, `DiskDrive.blankStorage`) when the loader
first asks for a storage disk. The loader's *C* (“to Create a New STORAGE
disk, insert a BLANK disk and press C”) formats the storage disk, after the
game's own warning that it will be erased.

What the game writes stays with the drive; after each run of the loop the
viewer keeps a written disk in the app's own folder, `Application
Support/Storage Disks/` in the app's container (`StorageDisks`), under the
disk's name, and reads its saved games again (the sidebar's *Saved games*).
At launch the app loads that folder first; a storage disk of a name already
loaded is left out, so the app's copy stands in for the bundled `save.dsk`
or a disk opened, which stay as they were.

## What differs from the worlds the app starts itself

The sidebar's worlds are built by `WorldBuilder` (levels 2‑5 from untouched
previous levels, by their exit code). A level entered through the loader is
the authentic one: the loader loads only the new level's rooms, texts and
code, so the previous level's code beyond the new one's end and the $1A50
piece's variables stay (WorldBuilder clears $0803‑$1FFF and reloads the
engine), track 0 sector 0 is at $0800‑$0802, BOOT_CHECK_RESULT is shifted
once more, and the objects and engine variables are as the player left them.
A world chosen in the menu keeps the menu's pictures where its own files
don't reach ($8ED9‑$8EEF for Level 1).

## Checked

`Data/loader_check.sh` drives the original loader headless (v1.1 4am crack
and v1.0, Ro1v10): levels 1‑4 run their exit code and the next level
arrives at its main loop and runs; Level 1 saves (Esc S) on a new storage
disk and the slot read back (`savedGames`) holds the world exactly as it was
at the exit; Esc Esc gives the menu, and each of its five worlds starts and
runs; the saved game restored from the menu (Robotropolis, O, A), after its
first tick, equals `WorldBuilder`'s saved game after its first (started with
the random generator where the restore found it) but for the loader's own
bytes (SLOTS_USED, BOOT_CHECK_RESULT, the boot sector at $0800,
COPY_PROTECTION_OK's low bits), bank 1 included; *C* makes a new storage
disk holding just the new game, the rest of it a blank storage disk's.
