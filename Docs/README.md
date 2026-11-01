# Robot Odyssey – Swift port: findings and plan

Reverse engineering of *Robot Odyssey I* for the Apple II (The Learning
Company, 1984), working from the original disk images, with the goal of a
faithful Swift version.

| Document | Contents |
|---|---|
| [DiskLayout.md](DiskLayout.md) | disks and versions, the custom loader, every file on the v1.x disks, saved games |
| [WorldFormat.md](WorldFormat.md) | the world image $6000‑$94FF: objects, sprites, rooms, walls, texts, wires, colours, font, exact drawing rules |
| [Engine.md](Engine.md) | memory map, the main loop (tick), draw phase, timing, the hybrid engine, porting strategy |
| [Robots.md](Robots.md) | robot drawing ($D2BC/$D72B): robot state, the three engine builds, the random generator, verification |
| [Sound.md](Sound.md) | the sound player: the queue, tone and noise loops, every world's sounds, the native port and the speaker |
| [CopyProtection.md](CopyProtection.md) | the copy protection: the E7 bitstream on track 1, the checks, the flag that turns off the soldering pen, the cracked dumps |
| [Symbols.md](Symbols.md) | the symbol maps: how the code is shared between worlds and versions, names and addresses, the loader's code check, mapping a new routine |
| [../Data/README.md](../Data/README.md) | the Python tools, extracted data, Mariani symbol files |

## Current status (2026‑11‑01)

* **Viewer app** (macOS, SwiftUI): opens the v1.0/v1.1 disk images and storage
  disks, shows all nine worlds and the saved games room by room, with
  inspector, hover read‑out and exits; the rooms in an 8×8 grid or on a map
  of how they connect.
* **The game runs and can be played.** Each world's main loop
  runs on the 6502 emulator as in the game, tick after tick at the original
  speed (4‑7 ticks/s, paced by CPU cycles at 1.0205 MHz): robots, circuits
  and the worlds' own code animate. Any room can be watched. With *Play*
  the keyboard goes to the game (I J K M or the arrow keys, space, `?`,
  Esc…) and the view follows the player; leaving a world (menu, next level,
  saving) stops the loop, as the loader is not emulated yet.
* **Input:** the Apple's keyboard, joystick (paddle timers by CPU cycles)
  and buttons are emulated in `Machine`; the viewer uses the keyboard.
* **Hybrid engine:** level and room code always runs as original 6502 code;
  ported to Swift so far: the robot drawing, the input (READ_INPUT and the
  levels' player routines), the object motion (moving objects across
  rooms, walls, screen edges, Engine.md "Input") and the sound player.
* **Sound** (Sound.md): the native PLAY_SOUNDS runs the tone and noise loops
  as the original, reports every speaker click to the cycle and takes the
  sound's cycles (the game waits while a sound plays, as on the Apple); the
  viewer makes the speaker's sound from the clicks (*Sound* in the toolbar).
  The 37 sounds of the worlds' tables are named in `GameSounds`.
* **Copy protection** (CopyProtection.md): the worlds skip the soldering
  pen unless the loader's flag says the disk passed the check; the app
  loads every world with the flag set, as an original disk does.
* **Symbol maps** (Symbols.md): every address the Swift code uses, with its
  place in each engine build and version, is in `RobotOddyssey/Symbols`
  (game, loader, Level 1's code); the native routines use the names
  (`m.robotX = m.objX[body]`) and the Mariani `.sym` files are written from
  the maps. The loader tells the version by its file table and, loading a
  world, checks the fingerprint of every routine a native replaces: a
  routine that differs (a modified disk) runs as 6502 code, an unknown
  version runs on the original code only.
* **Verified:** every native routine against the original code
  (`Data/native_check.sh`), per drawn room, per direct call (memory, and
  registers and flags for the routines the worlds' code calls; cycles and
  speaker clicks for the sound) and over whole ticks with and without input:
  v1.1 670 frames, 440 ticks, 3,300 ticks with input, 53,920 calls (1.45 M
  clicks); v1.0 542 frames, 360 ticks, 2,700 ticks with input, 43,680 calls
  (1.18 M clicks) – all identical.
* **Next:** porting the tick's engine routines one by one (grabbing, linked
  objects, robots, wires, gates, chips), each checked tick by tick against
  the original; natives' cycle counts (pacing); the loader (level changes,
  save/load).

## What we know so far

* The disks have **no DOS**. A track‑1 loader ($4A20) loads files by
  (track, sector, address, length) from a table. All files and their load
  addresses are known for v1.0/v1.1, both sides.
* A **world** is one memory image at $6000‑$94FF with the same layout for
  levels, tutorials, the lab and saved games: 256 objects, 64 sprites, 64 rooms
  (links, colours, 20×12 wall bitmap), 128 texts, robots and wires.
* **Levels 2‑5 are not stand‑alone.** They load only rooms and texts. The
  objects carry over from the previous level, rearranged by that level's
  exit code. We rebuild them by running that code on a 6502 emulator.
* Each world comes with its own **6502 code** (main loop, puzzles,
  animations) at $0803 and $8EF0; the engine itself is shared: engine main
  ($9500‑$B7D6) is one file for every world and version, the rest comes in
  three builds (levels, Robot Anatomy/Toolkit, lab) of the same code with
  the variables elsewhere, and v1.0 differs from v1.1 only in the language
  card's $D000 bank, by a few shifted routines (Symbols.md).
* **Rendering is solved exactly.** Walls, sprites, texts and the L‑shaped
  wires match the original drawing routines byte for byte (all 64 rooms of
  the save state, run on the emulator).
* **Timing:** one main‑loop iteration is one tick. There is no vertical‑blank
  sync, so the original runs at about 4‑7 ticks/s depending on the room.
  Circuits only depend on the per‑tick update order.
* Saved games (storage diskette) are fully decoded and can be viewed and run.
* **After loading, the loader sets up the chips** (8 chip programs in
  language‑card RAM, a chip table at $F008); without that the chip
  interpreter never ends a tick. Restoring a game puts the chip table and
  four engine variables back from the save's header (DiskLayout.md).
* With no joystick plugged in, the engine plays by keyboard (it tests the
  paddle timer at $AC24) but keeps reading the paddles, and switches to the
  joystick when they change. Keys move the player by one step a tick
  (7 across, 16 up or down, 1 with Ctrl); the movement keys are a table
  each world sets (Engine.md "Input").
* **Hybrid engine.** The original code runs on the 6502 emulator with the
  language card; engine routines are replaced by native Swift routines one at
  a time, each bound to the MD5 of the code it replaces and checked byte for
  byte against it. The robot drawing is the first (Robots.md); level and room
  code stays original. The viewer runs each world's main loop and shows any
  room as the world's own draw phase draws it, so robots, puzzle sprites and
  code rooms look and move as in the game.

## Plan

**Phase 1 – data and viewer (done)**
- [x] disk access with the game's sector order, file table, world catalog
- [x] world format, extraction script, JSON/PNG output
- [x] 6502 emulator (Python and Swift) for level transitions and tests
- [x] Swift viewer: open the .dsk images (and storage disks), browse worlds
      and rooms by number, follow exits, inspect objects/texts/wires
- [x] Mariani symbol files
- [x] the loader's set‑up after loading (chips, chip table), restoring saved
      games (header), v1.0's file lengths

**Chip view (viewer, planned)** – a *Chips* section below the rooms. The
chips are netlists without coordinates (the lab's placement is lost when a
chip is burned), so it comes in two stages:
- [ ] stage 1 – no layout needed: a Swift parser for the chip bytecode
      (`Data/ro_chip_disasm.py` as reference, checked against
      `Data/Extracted/v1.1/chips.txt`); the 8 chip slots as 8‑pin boxes
      (directions from $F008, live pin values, empty slots greyed); the
      selected chip's parts in program order like `chips.txt`, every input
      and output with its live value, nested chips foldable. Inputs are bytes
      inside the program, so in *Game* mode re‑reading $D000‑$EFFF (bank 1)
      each tick animates it. Doubles as the reference view for porting $F56B.
- [ ] stage 2 – after $F56B is understood: a schematic with automatic layout
      (layers left to right from the input pins, feedback cut at the
      flip‑flops, fewer crossings, nested chips as boxes), showing the timing
      too (the extra tick across a nested chip's pins)

**Phase 2 – understand the engine**
- [ ] name every routine of the tick (start from `RobotOdyssey.sym`)
- [x] robot drawing: exteriors and interiors in all three engine builds
- [ ] robots: thrusters, bumpers, grabbers, antennas, batteries (behaviour)
- [ ] circuits: gate types ($8CB7), flip‑flops, chips and burning (lab),
      the $7780 table and the chip pin lines ($8A82) – known so far: 8 chip
      programs at $D000 + $400n, run up to opcode 7 by $F56B; their bytecode
      (PC CHP format) and the pin direction table $F008 are decoded
      (Engine.md "Chips", `Data/ro_chips.py`)
- [x] input: keyboard, joystick, buttons, movement keys (Engine.md "Input")
- [x] object motion: moving across rooms, walls, screen edges
- [ ] player: grabbing, entering robots, remote control/solder pen
- [ ] level scripts: what each world's $0803/$8EF0 code does
- [ ] v2.0 disks (other loader and engine layout)

**Phase 3 – port the game logic**
- [x] `Machine`: original code on `CPU6502` with language card banks, soft
      switches and native routines (traps); each world's draw phase runs
- [x] whole ticks on `Machine` (`GameLoop`, the reference engine): every
      world's main loop runs as in the game – without input so far
- [x] input: keyboard ($C000), joystick (paddle timers) and buttons in
      `Machine`; the world's exit to the loader stops `GameLoop`
- [ ] native Swift engine, routine by routine – done: robot drawing, input
      (READ_INPUT, the levels' player routines), object motion
- [x] per‑routine checks: native vs original on random states and every
      drawn frame (`Data/native_check.sh`)
- [x] lock‑step over whole ticks without input: native vs original, memory,
      bank 1 and screen after every tick (`native_check`, 40 ticks per world)
- [x] the same with input sequences (keys, joystick, buttons; 300 ticks per
      world) – this is what guarantees that circuits behave identically
- [ ] natives' cycle counts, so ticks with natives take the original's time
- [x] tick pacing: authentic (cycle based, in the viewer)
- [ ] tick pacing: fixed rate, fast

**Phase 4 – the game**
- [x] keyboard (viewer *Play*)
- [x] sound (Sound.md)
- [ ] game controller as joystick, menu, level changes, save/load
- [ ] optional extras: larger window, zoom, better colours, debugging tools

## The viewer app

Open the side A and B images (or the folder) with *Open Disk Images…* or by
dropping them on the window; storage disks with saved games can be added.
The app remembers the disks (macOS). At launch it first loads every `.dsk` in
`RobotOddyssey/Resources/` (bundled with the app, ignored by git – locally
`diskA.dsk`/`diskB.dsk` = the 4am crack of v1.1, side A/B), then the remembered disks. Each
version keeps one side A and one side B: the first one loaded wins, later
sides of the same version are ignored (listed under *Notes*). Without disks
the window shows the game's title screen (`Data/ro_title.py`); the app icon is
robot 2, the blue one, as the engine draws it (`Data/ro_icon.py`). Pick a world in the sidebar and a room
below the canvas: *Grid* shows all 64 rooms (room *n* at column *n*%8, row
*n*/8), *Map* shows the rooms as they connect (`WorldMap`), scrollable and
zoomable, with each room's number on it. It leaves out links to and from the
robots' interiors ($09‑$0B, $0D in the levels: the player gets in and out by
the robot) and $3F (nowhere: Level 4's edges lead there, and its code takes
$3F for no exit). The links never change while a world runs; the walls do
(SET_WALL $B3AA: doors, the Lab's paintbrush, Level 5 opens the top of the start room), so an
edge walled up from end to end keeps its exit (Level 2's $3A↓$3D). The links
don't always form a plane (the sewer mazes lead back into themselves, Level 2's
subway wraps around, some exits are one‑way), so the map is
the layout found to show the most exits as rooms next door (a two‑way exit
counts twice): the rooms are placed best first, each where it shows the most
exits to the rooms placed so far, then moved, alone or with the rooms they
show exits to, by simulated annealing with a fixed seed (the same map every
time, 3–70 ms per world). An exit that doesn't lead to the room next door is
a yellow badge on that edge (click it to go there). Rooms shown next to each
other form an island, the player's first; rooms without exits (robot
interiors, chip and code rooms) follow as in the grid.
`Data/ro_map.sh` prints every world's map as text, with how many exits it
shows (v1.1: Level 1 64 of 72, Level 2 136/170, Level 3 87/118, Level 4
174/192, Level 5 76/93; before leaving out the robots' interiors and $3F,
growing breadth first from the player's room showed 60, 132, 80, 155, 70). The map keeps
the selected room in view, so when playing it follows the player. Arrow keys
follow exits. Hover shows object coordinates and the sprite or wire under
the pointer. Click a sprite or a wire to select it in the inspector (the
canvas outlines it in yellow). The inspector shows the room's properties,
the game, then the room's contents as the loop last drew the room: the
world's state where the draw phase of the page on screen started
(`GameLoop.memory`), so objects the code moves or turns into other sprites
(Level 1's room $0E rewrites sprites $29 and $2C into a robot in its first
tick) show as they are drawn, and wires as hot (orange, colour 5: the only
colour the gates and thrusters take for on) or off. *Objects*, *Other
sprites drawn*, *Wires* and *Texts* are folded like the native routines.
While *Other sprites drawn* is open (and
the inspector shown) the draw phase runs once more each tick, as 6502 code
only, and every DRAW_SPRITE is recorded with the routine of the main loop
that drew it (`GameLoop.sprites`): objects (DRAW_ROOM_OBJECTS), robots
(DRAW_ROBOTS, DRAW_ROBOT_INTERIOR) and the world's own code (by address);
the texts' letters are left out. That takes about 1 ms per tick (10 ms in a
Debug build); then hover and click work on every sprite, otherwise on the
objects. Code rooms, which the loop doesn't draw, list the world as it starts.

The world's main loop runs on the emulator (with the
native routines) as in the game: each tick takes the CPU cycles it takes at
1.0205 MHz, so every room runs at its original speed, and the canvas shows
the hi‑res page on screen. The selected room is drawn by the world's draw
phase in place of the player's room, while the rest of the tick runs as in the
game; on a room change the room appears at once, drawn from the state at the
start of the tick. The toolbar has *Pause/Run* (also the space bar), *Step*
(one tick, when paused) and *Restart*; the inspector's *Game* section shows
the tick and ticks/s, how the room is drawn and, folded, the native routines
in use with their entry points (and any routine the loader found modified,
which runs as 6502 code). The room thumbnails show the rooms after the world's
start‑up code; the selected room is shown live, and a room keeps its last
live frame once you leave it, so the map shows the rooms as last seen. A room
the player walks out of while playing is drawn again a tick later, without
the player.
The thumbnails and the map are made off the main thread when the world or the
display mode changes (`ViewerModel.prepareRooms`; in a Debug
build the 6502 takes 1–2 s to draw all rooms and the map up to 1 s), with a
progress indicator in their place meanwhile. For that the engine, symbol,
rendering and model types are `nonisolated` (the app target's default
isolation is the main actor); the viewer stays on the main actor.

*Play* sends the keyboard to the game and makes the view follow the player.
Keys are typed on the Apple's keyboard as they are (letters, digits, Ctrl,
Return, Esc, Tab; Delete is ←), so I J K M move, Ctrl‑I J K M move slowly,
space picks up and drops, `?` gives hints and Esc asks to quit. The arrow keys
move like I J K M, and with Shift slowly, as in the PC version (the Apple's
own arrow keys send codes the game takes for other keys). When a world hands
back to the loader (the menu, the next level, saving) the loop stops;
*Restart* starts it again. *Step* stops inside a tick that waits for a key. *Sound* plays the game's sounds
(the game stops while one plays, as on the Apple; Ctrl‑S is the game's own
switch), and the status shows the last one. Code rooms, and rooms the
world's code fails to draw, are drawn by `RoomRenderer` (tiles, texts,
objects, wires).

In Debug builds `-openDisks <path>…` opens disks at launch (needs
`ENABLE_APP_SANDBOX=NO`).

The extracted data, the Python tools and the app read **your own disk
images**; nothing from the game is part of the app. `Data/Extracted` is game
data – keep it out of public repositories.
