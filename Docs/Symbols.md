# Robot Odyssey I (Apple II) – Symbols

Every address the Swift code knows is in one place, the symbol maps in
`RobotOdyssey/Symbols`: each variable, table, sprite and routine by name,
with its address in every engine build and version, and for each routine a
native replaces, the fingerprint of its code. The native routines use the
names, the loader checks the fingerprints when it loads a world, and the
Mariani `.sym` files are written from the same maps (`Data/ro_symbols.sh`).

## How the code is shared

| Part | Where | Shared by |
|---|---|---|
| engine main | $9500‑$B7D6 (drawing, text, object motion, input) | every world, v1.0 and v1.1: one file, byte for byte |
| engine build *levels* | $1A50, $B8E0, $D000, $F000 (side A) | Levels 1‑5 and their saved games |
| engine build *kit* | $B900, $D000, $F000 (side B; its robot state in the $14C0 code) | Robot Anatomy, Toolkit |
| engine build *lab* | $B8E0, $D000, $F000 (side B; robot state in the $0B00 code) | Innovation Lab and its tutorial |
| world code | $0803, $8EF0 (levels), $0B00/$14C0 (side B) | one world each |
| loader | $4000‑$5DFF (tracks 0‑1) | everything; the same addresses in v1.0 and v1.1 |

The three engine builds are the same code assembled with their variables,
tables and sprites in other places (the robot drawing at $D2BC in the
levels, $D2AB in the kit and the lab, its variables at $8Exx, $1Bxx and
$13xx). Each engine file is assembled for one load address, so a code
address names the same instruction in every world of a build.

Between v1.0 and v1.1 **only the language card's $D000 bank** changed: engine
main, $1A50, $B8E0/$B900 and $F000 are identical. In the levels' $D000 bank
v1.0 has a few bytes more, so everything from DRAW_INTERIOR_PARTS on is 1‑4
bytes later (DRAW_INTERIOR_PARTS $D7D1, ROBOTS_THRUSTERS $D834, ENG_DA44
$DA46, ENG_DA90 $DA93, ROBOTS4_UPDATE $DE11, CRYSTALS $DE96, CRYSTALS2
$DF82, PLAYER_WALK_SPRITE $DFA4; DRAW_ROBOTS and PLAYER_IN_ROBOT stay).
Level 1's v1.0 code calls exactly these addresses; otherwise it is v1.1's
(the same addresses, `Level1Symbols`). The kit's and the lab's $D000 banks
move from $DA1E and $D9B7 on (PLAYER_IN_ROBOT $DC11 and $DBA7 in v1.0), after
their robot drawing. The loader keeps its addresses; its file table differs
in eight lengths (DiskLayout.md).

None of the worlds' start‑up code changes engine code (it sets MOVE_KEYS,
FLAG_9C51, DRAW_VECTOR and the vector at $A66D), so the engine code can be
checked as it comes from the disk.

## The maps

* `GameSymbols` – the game's memory: zero page, the world image
  ($6000‑$94FF), engine main, the three builds' pieces.
* `LoaderSymbols` – the loader (RobotOdysseyLoader.sym): boot stage 2, the
  loader's requests, saving and restoring, its prompts and the addresses of
  the app's loader natives (Loader.md); and how its file table tells the
  version.
* `Level1Symbols` – Level 1's own code, for the debugger (`L1_` names).
* `GameSounds` – the sounds the worlds play, by name, each with its
  parameters (tone or noise, length, sweep, pitch; several pitches where the
  code computes it): what the native PLAY_SOUNDS names what it played by
  (Sound.md). Data/ro_sounds.sh checks every world's sound table against it.

A symbol is a `Byte`, a `Word` (low byte first), a `Table` (bytes indexed
from the address), a `Sprite` (16 rows) or a `Routine`. Its `Address` is
either the same everywhere or given per engine, nil where an engine has
none, with v1.0's place where the code moved:

```swift
let moveDX = Byte(0x9C22)                                   // every world, every version
let robotX = Byte(levels: 0x8EBF, kit: 0x1BCF, lab: 0x1390) // per engine
let pulsePhase = Byte(levels: 0x8E9E)                       // the levels only
let drawInteriorParts = Routine(levels: 0xD7D0, kit: 0xD705, lab: 0xD705, levelsV1_0: 0xD7D1)
```

A world's engine and the disks' version make its `Variant`, which places
every symbol. The name of a symbol is its property's: `moveDX` is MOVE_DX in
the `.sym` files, `drawRobot2Scan` DRAW_ROBOT2_SCAN, `engDA44` ENG_DA44 (a
trailing address); a `guess` adds `_Q`. One name for Swift and the debugger.

## Native code by name

The native routines are methods of `Engine` (the machine as a native sees
it: memory `m`, registers `r`, the input devices). `m` is `RAM`, the CPU's
own memory with every symbol of the map as a property, in the world's
variant:

```swift
m.robotX = m.objX[body]           // a Byte is a UInt8, a Table indexes from its address
m.drawX = m.robotX &+ 3
m.spritePointer = m.blankSprite   // a Word is an Int, a Sprite its address
drawSprite(colour: 4)
```

Routines that take a variable as a parameter pass its symbol
(`limit(\.moveDX, to: \.limitX)`, then `m[move]`). Code that looks at a
memory image (the model, the viewer, the checks) reads symbols that are the
same everywhere straight from the array: `mem[\.currentRoom]`,
`mem[\.objRoom, o]`.

`m.robotX` compiles to a load from the map and a byte access; `RAM`'s
accessors are `@inline(__always)` so the compiler can fold the key path,
which needs whole‑module optimisation (Release builds; the scripts in Data
build with `-wmo`). The robot drawing takes about as long as before the
symbols (4.7 µs against 3.0 µs per call with three robots on screen); in
Debug builds it is about 4× slower than before.

## The loader's check

1. **Version.** `LoaderSymbols.version(of:)` hashes the file table's entries
   ($4D5E‑$4EE9) from track 1: one MD5 for every known v1.0 dump, another
   for both v1.1 sides. The cracks patch the loader's code, not its table.
2. **Variant.** `WorldBuilder` loads a world with its engine
   (`WorldDefinition.engine`; a saved game takes the matching level's), so it
   knows the variant.
3. **Fingerprints.** It checks every routine the natives need right after
   loading (`CodeCheck`): the MD5 of the routine's code ranges (variables
   inside left out) must be the variant's. `CodeCheck.natives` are the natives
   whose routines all match; `CodeCheck.differing` names the others.
4. **Install.** `GameScreen` installs exactly `CodeCheck.natives`. A routine
   whose code differs – a modified or damaged disk – runs as the original
   6502 code, and the natives that need it too; the viewer lists it under
   *Notes*. An unknown version gets no natives: the whole engine runs as 6502
   code, which works with any version the loader can load.

Tested with a copy of v1.1's side A where DRAW_ROBOTS draws the scanning
robot's bar in another colour: the five levels report DRAW_ROBOTS as
differing and run it as 6502 code, every other native still runs, and the
frames and ticks are identical with and without natives.

## Natives

`Native.all` (Engine/Natives.swift) lists each native: the routine it
replaces, the routines it reproduces besides (`uses` – what it calls or
falls into, e.g. READ_INPUT uses the object motion), whether callers use the
registers it leaves (`leavesRegisters`, compared by native_check), and the
method to run. A native may report the cycles the original takes
(`Engine.elapsed`; PLAY_SOUNDS does) and the sounds it played
(`Engine.sounds`). Each listed routine has its code ranges and MD5s in
GameSymbols.

## Mapping a new routine

1. Name its variables, tables and entry in GameSymbols (one line each, per
   engine where they differ).
2. Give the routine its code: the ranges from its entry up to the next
   routine, without the variables between, with `md5: ""`:
   `Routine(0x9C53, code: 0x9C53 ..< 0x9C88, md5: "")`, or per engine with
   `.levels(…)`, `.kit(…)`, `.lab(…)` and `.levels(.v1_0, …)`.
3. `Data/ro_symbols.sh --code` on the v1.0 and v1.1 disks prints its MD5 in
   every variant (and whether all worlds agree); copy them in.
4. Port it as a method of `Engine`, add it to `Native.all` with what it uses,
   and run `Data/native_check.sh` on both versions.
5. `Data/ro_symbols.sh` rewrites the `.sym` files.

## Symbol files

`Data/ro_symbols.sh` writes them in the AppleWin/Mariani format (`ADDR NAME`,
CRLF; lines starting with `;` are comments):

| File | Names for |
|---|---|
| `RobotOdyssey.sym` | Levels 1‑5 and their saved games, v1.1. The `L1_` names fit Level 1's code only: levels 2‑5 have other code at $0800‑$1FFF and $8EF0 |
| `RobotOdyssey_v1.0.sym` | the same for v1.0 |
| `RobotOdysseyKit.sym` | Robot Anatomy, Toolkit (v1.1; v1.0's differ only where no symbol is yet) |
| `RobotOdysseyLab.sym` | the Innovation Lab and its tutorial (likewise) |
| `RobotOdysseyLoader.sym` | boot stage 2, the loader, the menu, saving and restoring ($4000‑$5DFF). During play that area is hi‑res page 2, so keep these names off there |

### In Mariani

Mariani (1.5) has AppleWin's debugger: *Window → Show Debugger* (F7). Its
*Debugger Command Line* takes AppleWin's commands, and the console shows
their output. How it finds symbol files (Mariani's source,
[sh95014/AppleWin](https://github.com/sh95014/AppleWin): `CmdSymbolsLoad`,
`DebugInitialize`, `source/frontends/mariani`):

* Its program folder is `~/Library/Application Support/<bundle id>/`. For
  the installed Mariani that is `com.applewin.marianipro`
  (`CFBundleIdentifier` in the app's Info.plist).
* `SYMUSER LOAD "name"` reads *name* in that folder. The name is appended to
  the folder's path, so an absolute path doesn't work (`RUN` takes one,
  `SYM… LOAD` doesn't).
* When the emulator starts, it loads `A2_USER1.SYM` from that folder into
  the User 1 table, next to its own `APPLE2E.SYM` (ROM, I/O, zero page) and
  `A2_BASIC.SYM` (Applesoft), and runs `DebuggerAutoRun.txt` from there once.

**Setting up:** run `Data/ro_mariani.sh` once (with the app's path if it
isn't in /Applications or ~/Applications), then restart Mariani. It finds
the program folder from the app's bundle id and puts there:

* links to the five `.sym` files, so Mariani always reads what
  `ro_symbols.sh` last wrote;
* `A2_USER1.SYM`, a link to `RobotOdyssey.sym`: the levels' names load by
  themselves;
* a `DebuggerAutoRun.txt` with the loader's names in the second user table,
  off until needed, and Applesoft's names off:

  ```
  SYMUSER2 LOAD "RobotOdysseyLoader.sym"
  SYMUSER2 OFF
  SYMBASIC OFF
  ```

It leaves an `A2_USER1.SYM` that isn't a link and an existing
`DebuggerAutoRun.txt` alone.

**Commands** (the debugger takes a name wherever it takes an address):

| Command | |
|---|---|
| `SYMUSER CLEAR`, then `SYMUSER LOAD "RobotOdysseyKit.sym"` | another world's names, or the levels' again after `ro_symbols.sh`. LOAD adds to a table: without CLEAR, names dropped since stay and every name already there is listed as a duplicate |
| `SYMUSER2 LOAD "RobotOdysseyLoader.sym"` | the loader's names in a second table |
| `SYMUSER2 ON` / `SYMUSER2 OFF` | show them in the loader, hide them during play |
| `SYMBASIC OFF` | hides Applesoft's names. They cover $D000‑$F7FF, where the game runs its language‑card code, and would name addresses our files don't |
| `SYM L1_SHUFFLE_OBJECTS` | look up a name (or an address) |
| `BPX L1_MAIN_LOOP` | breakpoint: one stop per tick |
| `BPMW L1_SHUFFLED`, `BPM CURRENT_ROOM` | stop when a variable is written, or read or written |

Notes:

* The user tables are searched before the ROM's and Applesoft's (AppleWin
  looks from the last table to the first), so where two tables name an
  address, ours wins. A table turned OFF names nothing in the disassembly.
  `APPLE2E.SYM`'s monitor names ($F800‑$FFFF) still label the engine's
  code there wherever our files have no name; its I/O names ($C0xx) are
  worth keeping.
* Loading prints a line for each of our names on an address another table
  names (`Info.: … aliases …`), and a warning for names longer than 20
  characters (23 in `RobotOdyssey.sym`, e.g. SHIFTED_SPRITE_ROUTINES). Both
  are only notes: the names load.
* *Go to Symbol* (top of the window) lists the names of every table, ON or
  OFF. It copies them the first time the window opens: names loaded later
  show in the disassembly at once, but in that list only after Mariani
  restarts. Hence the `A2_USER1.SYM` link.
