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
| [../Data/README.md](../Data/README.md) | the Python tools, extracted data, Mariani symbol files |

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
  animations) at $0803 and $8EF0; the engine itself is shared.
* **Rendering is solved exactly.** Walls, sprites, texts and the L‑shaped
  wires match the original drawing routines byte for byte (all 64 rooms of
  the save state, run on the emulator).
* **Timing:** one main‑loop iteration is one tick. There is no vertical‑blank
  sync, so the original runs at about 4‑7 ticks/s depending on the room.
  Circuits only depend on the per‑tick update order.
* Saved games (storage diskette) are fully decoded and can be viewed.
* **Hybrid engine.** The original code runs on the 6502 emulator with the
  language card; engine routines are replaced by native Swift routines one at
  a time, each bound to the MD5 of the code it replaces and checked byte for
  byte against it. The robot drawing is the first (Robots.md); level and room
  code stays original. The viewer draws rooms by running each world's own
  draw phase, so robots, puzzle sprites and code rooms look as in the game.

## Plan

**Phase 1 – data and viewer (done)**
- [x] disk access with the game's sector order, file table, world catalog
- [x] world format, extraction script, JSON/PNG output
- [x] 6502 emulator (Python and Swift) for level transitions and tests
- [x] Swift viewer: open the .dsk images (and storage disks), browse worlds
      and rooms by number, follow exits, inspect objects/texts/wires
- [x] Mariani symbol files

**Phase 2 – understand the engine**
- [ ] name every routine of the tick (start from `RobotOdyssey.sym`)
- [x] robot drawing: exteriors and interiors in all three engine builds
- [ ] robots: thrusters, bumpers, grabbers, antennas, batteries (behaviour)
- [ ] circuits: gate types ($8CB7), flip‑flops, chips and burning (lab),
      the $7780 table and the chip pin lines ($8A82)
- [ ] player: movement, grabbing, entering robots, remote control/solder pen
- [ ] level scripts: what each world's $0803/$8EF0 code does
- [ ] v2.0 disks (other loader and engine layout)

**Phase 3 – port the game logic**
- [x] `Machine`: original code on `CPU6502` with language card banks, soft
      switches and native routines (traps); each world's draw phase runs
- [ ] whole ticks with input on `Machine` (the reference engine)
- [ ] native Swift engine, routine by routine – started: robot drawing
- [x] per‑routine checks: native vs original on random states and every
      drawn frame (`Data/native_check.sh`)
- [ ] lock‑step tests over whole ticks: same input to both, compare the world
      after every tick (this is what guarantees that circuits behave identically)
- [ ] tick pacing: authentic (cycle based), fixed rate, fast

**Phase 4 – the game**
- [ ] input (keyboard, game controller), sound, menu, save/load
- [ ] optional extras: larger window, zoom, better colours, debugging tools

## The viewer app

Open the side A and B images (or the folder) with *Open Disk Images…* or by
dropping them on the window; storage disks with saved games can be added.
The *Game* renderer runs the world's draw phase on the emulator (with the
native routines); *Static* uses `RoomRenderer` (tiles, texts, objects, wires).
The app remembers the disks (macOS). Pick a world in the sidebar and a room
in the 8×8 map (room *n* is at column *n*%8, row *n*/8). Arrow keys follow
exits. Hover shows object coordinates. Click an object to select it in the
inspector, and the inspector lists all objects, wires and texts.

In Debug builds `-openDisks <path>…` opens disks at launch (needs
`ENABLE_APP_SANDBOX=NO`).

The extracted data, the Python tools and the app read **your own disk
images**; nothing from the game is part of the app. `Data/Extracted` is game
data – keep it out of public repositories.
