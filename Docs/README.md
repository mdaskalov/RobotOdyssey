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
| [Loader.md](Loader.md) | the loader in the app: boot stage 2, the loader and the menu as 6502 code with a native boot, RWTS and disk drive; the storage disk; following the game into the next world |
| [Symbols.md](Symbols.md) | the symbol maps: how the code is shared between worlds and versions, names and addresses, the loader's code check, mapping a new routine, the `.sym` files in Mariani's debugger |
| [Frontends.md](Frontends.md) | plan: switches for the natives with a live check against the original, the native layer (the Mac drawing the texts, sprites, plots and lines over the rest of the page) beside the Apple's, modern sound |
| [../Data/README.md](../Data/README.md) | the Python tools, extracted data, Mariani symbol files |

## Current status (2026‑11‑01)

* **Viewer app** (macOS, SwiftUI): opens the v1.0/v1.1 disk images and storage
  disks, shows all nine worlds and the saved games room by room, with
  the *Current Room* panel, hover read‑out and exits; the rooms in an 8×8 grid or on a map
  of how they connect.
* **The game runs and can be played.** Each world's main loop
  runs on the 6502 emulator as in the game, tick after tick at the original
  speed (4‑7 ticks/s, paced by CPU cycles at 1.0205 MHz): robots, circuits
  and the worlds' own code animate. Any room can be watched. With *Play*
  the keyboard goes to the game (I J K M or the arrow keys, space, `?`,
  Esc…) and the view follows the player. Each tick's page is on screen as
  the tick starts (a tick earlier than on the Apple), and *Smooth* shows
  what moves gliding between two ticks' pages, drawn by the game's own draw
  phase, frame by frame of the display.
* **The loader runs** (Loader.md): where a world hands back to it, the
  Apple boots again and boot stage 2, the loader and the menu run as 6502
  code, with natives for the boot ROM, RWTS on a disk drive (the program
  sides, a storage disk) and the copy checks. The next level, the menu and
  its worlds, saving and restoring games, loading and saving chips work as
  on the Apple, prompts included; the viewer follows the game into the
  world the loader starts. Saved games go to `save.dsk` (or the first
  storage disk loaded; made if there is none), kept in the app's
  Application Support folder and loaded from there at launch.
* **Input:** the Apple's keyboard, joystick (paddle timers by CPU cycles)
  and buttons are emulated in `Machine`; the viewer uses the keyboard and a
  game controller as the joystick (the further the stick is pushed, the
  faster the player moves, by the game's own joystick table). The mouse
  (Frontends.md "Input") is an Apple mouse card (`AppleMouse`, slot 4) for
  the game's own mouse mode: in *Play* a press of ⌘ alone hides the
  pointer, the mouse walks the player at the game's pace
  (at most 7 across and 15 up or down a tick, walls stop it), its button is
  the game's, one tick per press as the space key (take, drop, the
  toolbox, the remote, the soldering pen); ⌘ gives it back.
* **The 6502** (the `MOS6502` package, github.com/mdaskalov/MOS6502, with its
  README; in the project since 2026‑11‑03): the NMOS 6502 as AppleWin/Mariani runs it – all 256 opcodes,
  the undocumented ones too, as `Opcode` values (no more parsed table),
  AppleWin's cycles, each read or write on its bus cycle. Against
  AppleWin's own `cpu6502.h` (the package's `Data/cpu_check.sh`): 2.56 M random
  instructions identical but where AppleWin's results aren't the 6502's
  (DCP/ISC's carry on a wrap, ARR in decimal mode; those match Tom Harte's
  SingleStepTests).
* **Hybrid engine:** level and room code always runs as original 6502 code;
  ported to Swift so far: the robot drawing, the input (READ_INPUT,
  DETECT_JOYSTICK and the levels' player routines), the object motion (moving objects across
  rooms, walls, screen edges, Engine.md "Input") and the sound player.
  Each native has a switch in the *Current Room* panel's *Native routines*
  (under *Engine*, with *All*; the loader's under *Loader*), kept between launches; off, the original code runs there from the
  next instruction on (Frontends.md). The loader's intro skip (PLAY_INTRO)
  has one too: off, Robotropolis' intro plays as on the Apple. The menu's
  drawing (DRAW_PICTURE, XOR_BLOCK) runs as natives too, so the intro's
  tunes don't wait for its pictures (Loader.md).
* **The native layer** (since 2026‑11‑05, Frontends.md): each page in three
  layers – the page as the game drew it, the page without what the texts,
  sprites, plots and lines drew (DRAW_TEXT, DRAW_BIG_TEXT, DRAW_SPRITE, PLOT,
  HORIZONTAL_LINE, VERTICAL_LINE), and those drawings drawn by the Mac at
  its resolution over it, in the game's order: the texts in a modern
  monospaced font (SF Mono Medium) at the Apple's letter size, in place of
  the one‑pixel font the colour screen fringes in purple and green, the rest
  as the Apple's pixels, drawn on the page without them in the game's order
  with whatever else was written between them and coloured as the page is
  (`LayerPixels`, Apple2Kit's `Screen.image`): the same pixels with their switches on and
  off. The game draws everything into its page as ever. Each routine is a
  native that draws on layer 3 (`Native.Flags.drawsOnLayer3`), with its
  switch in *Native routines*, marked.
* **Sound** (Sound.md): the native PLAY_SOUNDS runs the tone and noise loops
  as the original, reports every speaker click to the cycle and takes the
  sound's cycles (the game waits while a sound plays, as on the Apple); the
  viewer makes the speaker's sound from the clicks (*Sound* in the toolbar),
  streamed to the cycle as the machine runs, so the 6502 code's own clicks
  (the loader's tunes, the intro, PLAY_SOUNDS switched off) keep their time
  (since 2026‑11‑03; before, the loader's were played a tune at a time once
  it had ended, seconds after its picture).
  The 37 sounds of the worlds' tables are named in `GameSounds`.
* **Copy protection** (CopyProtection.md): the worlds skip the soldering
  pen unless the loader's flag says the disk passed the check; the app
  loads every world with the flag set, as an original disk does.
* **Symbol maps** (Symbols.md): every address the Swift code uses, with its
  place in each engine build and version, is in `RobotOdyssey/Symbols`
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
  v1.1 542 frames, 360 ticks, 2,700 ticks with input, 45,480 calls (1.17 M
  clicks); v1.0 with the two saved games 670 frames, 440 ticks, 3,300 ticks
  with input, 56,120 calls (1.44 M clicks) – all identical.
* **Saved games** are read as RESTORE_GAME restores them: the header is a
  slot's last page (until 2026‑11‑01 the page before the slot was read),
  the engine and the level code come from the program disk
  (DiskLayout.md). `Data/loader_check.sh` checks the loader: next levels,
  menu, save, restore (equal to `WorldBuilder`'s saved game after a tick),
  a new storage disk, the intro played (its tunes streamed as the viewer
  does them), the game's sounds played as the viewer does (no pause, no
  click), the menu's drawing natives call by call; v1.0 and v1.1.
* **Next:** porting the tick's engine routines one by one (grabbing, linked
  objects, robots, wires, gates, chips), each checked tick by tick against
  the original.

## What we know so far

* **Easter egg:** Ctrl‑A, Ctrl‑L, T (capital) typed in the menu make Ctrl‑E
  turn the walls off and on for the player in levels 1‑5 (taking or putting
  down a tool turns them back on; Robot Anatomy has Ctrl‑E without the code).
  Engine.md, *Easter egg: walking through walls*. It works in the app: with
  *Play*, Esc Esc in a level, the code in the menu, then Robotropolis.
* **Level 1's black crystal** (object $04, room $07) is black on the black
  floor, so it can't be seen; brought to the Ampire Bot (Level 1's code, not
  an object) it stops the bot for good, as the *?* hint says (“Black
  crystals foil Ampire Bots”). Engine.md, *Level 1: the Ampire Bot*.
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
- [x] natives take no cycles (but PLAY_SOUNDS): faster where they run, by
      design (2026‑11‑03); what a tick does stays the original's
- [x] tick pacing: authentic (cycle based, in the viewer)
- [ ] tick pacing: fixed rate, fast

**Phase 4 – the game**
- [x] keyboard (viewer *Play*)
- [x] sound (Sound.md)
- [x] menu, level changes, save/load (the original loader, Loader.md)
- [x] game controller as joystick
- [ ] optional extras: larger window, zoom, better colours, debugging tools

## The viewer app

Open the side A and B images (or the folder) with *Open Disk Images…* or by
dropping them on the window; storage disks with saved games can be added.
The app remembers the disks (macOS). At launch it first loads the storage
disks the game wrote (the app's copies, Loader.md), then every `.dsk` in
`RobotOdyssey/Resources/` (bundled with the app, ignored by git – locally
`diskA.dsk`/`diskB.dsk` = the 4am crack of v1.1, side A/B, and `save.dsk`, a
storage disk with two saved games), then the remembered disks; a storage disk
of a name already loaded is left out. Each
version keeps one side A and one side B: the first one loaded wins, later
sides of the same version are ignored (listed under *Notes*). Without disks
the window shows the game's title screen (`Data/ro_title.py`); the app icon is
robot 2, Scanner, the blue one, as the engine draws it (`Data/ro_icon.py`). Pick a world in the sidebar and a room
in the *World* panel below the canvas (`WorldPanel`, shown or hidden from the
toolbar). Its sections fold like the *Current Room* panel's, their headers stay on top
as the panel scrolls: *Rooms* – *Grid* shows all 64 rooms (room *n* at column
*n*%8, row *n*/8), *Map* shows the rooms as they connect (`WorldMap`),
zoomable, with each room's number on it; *Wall types* – the tile patterns of
the rooms' walls and floors (the engine's colours, 8‑$13 dithered), each with
the rooms that use it (click: the next of them); *Sprites* – the world's 64
sprites as it starts, each in the colour of the first object that shows it
then (white if none), so wires and pins don't change colour there (click:
select the objects that show it, one after the other); *Sounds* – the world's sound table (Sound.md),
each with its name in the map, parameters and length, ▶ plays it as the game
does (also when muted); *Texts*, *Objects* (those in a room), *Robots* (the
levels: click the body, *Inside* for the interior) and *Wires* (hot or off) –
click one to go to its room and select it. Texts, objects, robots and wires
show the world as the loop last drew the selected room. The map leaves out links to and from the
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
the selected room in view while it is what the panel shows (its middle), so
when playing it follows the player; scrolled to the other sections, the panel
stays there. Arrow keys
follow exits. Hover shows object coordinates and the sprite or wire under
the pointer. Option‑ or Control‑click a sprite or a wire to select it in the
*Current Room* panel on the right (the canvas outlines it in yellow; a
press of ⌘ alone gives the game the mouse, Frontends.md "Input"). The
panel shows the room's properties (the floor and wall colours with their
tiles, the first object with its sprite, the last sound the game played),
the game, then the room's contents as the loop last drew the room: the
world's state where the draw phase of the page on screen started
(`GameLoop.memory`), so objects the code moves or turns into other sprites
(Level 1's room $0E rewrites sprites $29 and $2C into a robot in its first
tick) show as they are drawn, and wires as hot (orange, colour 5: the only
colour the gates and thrusters take for on) or off. *Objects*, *Other
sprites drawn*, *Wires* and *Texts* are folded like the native routines.
While *Other sprites drawn* is open (and
the *Current Room* panel shown) the draw phase runs once more each tick, as 6502 code
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
start of the tick. The loop runs frame by frame of the display (up to
60 Hz, `DisplayFrames`): as the clock reaches a tick, the whole tick runs at
once and its page is on screen right away; the next tick waits until the
clock has caught up, so the ticks keep their pace (`GameLoop.run`,
Engine.md). A key typed waits at most a tick, rather than up to two on the
Apple. *Smooth* (on by default) fills the frames between two pages: what
moved (the objects in the room, wire ends; a step's worth, as the player
walks) is put back part of the way and the draw phase draws the room from
where it drew the page (`GameLoop.inBetween`), so the page before turns into
the new one over the tick. The toolbar has *Pause/Run* (also the space bar), *Step*
(one tick, when paused) and *Restart*; the *Current Room* panel's *Game* section shows
the tick and ticks/s, how the room is drawn and, folded, the native routines
in use with their entry points (and any routine the loader found modified,
which runs as 6502 code), each with a switch; marked among them, the
routines whose drawing the Mac draws over the page as the rest of the code
drew it – the texts, sprites, plots and lines (Frontends.md "The native
layer"; the thumbnails and the map show the page as the game drew it). The room thumbnails show the rooms after the world's
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
own arrow keys send codes the game takes for other keys). A movement key
(the world's MOVE_KEYS) held down is typed again at the start of every tick
until it is let go, so the player walks on from the first tick, without the
Mac's key repeat delay. A game controller (`GameControllers`) is the
Apple's joystick with *Play*: the left stick or the d‑pad moves, A or X is
button 0, B or Y button 1 (either picks up and drops). The game moves the
player by how far the stick is pushed (Engine.md "Input"): a little, 1 step
a tick as with Ctrl; further, 2 then 4 across; all the way (and the d‑pad),
7 across and 15 up or down. A corner moves fully both ways, as the Apple
joystick's square gate does. The keyboard keeps working: a key switches the
game to the keyboard, moving the stick back to the joystick. The
*Current Room* panel's *Game* section names the controller. When a world hands
back to the loader (the menu, the next level, saving) the loader runs
(Loader.md): the canvas shows its screens, the keys go to it (the menu:
space or the arrow keys to choose, Return to load; the saving prompts; the
arrow keys are the Apple's there), and when it starts a
world the sidebar selects that world and the game goes on there; the
*Current Room* panel's *Drive* shows the disk in the drive and can insert another.
*Restart* starts the selected world again from its start‑up state. *Step*
stops inside a tick that waits for a key. *Sound* plays the game's sounds
(the game stops while one plays, as on the Apple; Ctrl‑S is the game's own
switch), and the status shows the last one. Code rooms, and rooms the
world's code fails to draw, are drawn by `RoomRenderer` (tiles, texts,
objects, wires).

In Debug builds `-openDisks <path>…` opens disks at launch (needs
`ENABLE_APP_SANDBOX=NO`).

The extracted data, the Python tools and the app read **your own disk
images**; nothing from the game is part of the app. `Data/Extracted` is game
data – keep it out of public repositories.
