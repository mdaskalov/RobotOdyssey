# Data – tools and extracted data

Python 3 scripts, no dependencies. Run them from this folder.

```sh
A="../RobotOdyssey/Resources/diskA.dsk"   # the current images: v1.1, 4am crack, side A
B="../RobotOdyssey/Resources/diskB.dsk"   # side B
STATE="path/to/ROv1.1_L1_SaveState.yaml"  # Mariani/AppleWin save state in Level 1 (from diskA)

python3 ro_extract.py "$A" "$B" Extracted/v1.1 [--rooms]   # all worlds -> bin/json/png
python3 ro_verify.py "$STATE"        # renderer vs. the original drawing code: 64/64 rooms identical
python3 ro_timing.py "$STATE" 20     # cycles per tick of the Level 1 main loop
./ro_symbols.sh                      # writes the .sym files from the app's symbol maps
./ro_symbols.sh --code "$A" "$B"     # each mapped routine's fingerprint in every world
./ro_mariani.sh                      # once: the .sym files into Mariani's debugger
python3 ro_chips.py "$A" "$B"        # disassemble the chips (also: STATE.yaml or a STORAGE.dsk)
./native_check.sh "$A" "$B" [STORAGE.dsk]   # native Swift routines vs. the original code
./ro_sounds.sh [--wav DIR] "$A" "$B"   # the worlds' sound tables, every sound native vs. original (WAVs)
./ro_map.sh "$A" "$B"                # every world's map (WorldMap) as text: exits shown, islands, badges
./loader_check.sh [--png DIR] "$A" "$B"   # the loader on the emulator: next levels, menu, intro, game sounds, menu natives, save, restore, new storage disk
./mouse_check.sh "$A" "$B"            # the mouse card (AppleMouse): plugging in and out, walking at the game's pace, keys, clicks, soldering, carrying
./layer_check.sh "$A" "$B"            # the native layer: memory as without it, every room's layer 2 against the page without the layer's routines, the help
./ro_dump.sh DIR "$A" "$B"            # every world's memory as its main loop starts, to disassemble
python3 ro_title.py "$A" Extracted/v1.1 [--verify]   # title screens -> title_N.png/.bin
python3 ro_icon.py "$STATE" ../RobotOdyssey/Assets.xcassets/AppIcon.appiconset   # app icon
python3 ro_shuffle.py "$A" "$B" ../Docs/crystal_spots.png   # Level 1: the black crystal's six spots
```

## Scripts

| Script | Purpose |
|---|---|
| `ro_disk.py` | read .dsk images in the game's sector order (`Disk.read(page, count)`) |
| `ro_catalog.py` | file catalog of v1.0/v1.1: every world's segments, engine pieces, level exit entries |
| `ro_world.py` | build world memory images (incl. levels 2‑5 via the exit code on the emulator) and decode them |
| `ro_render.py` | draw a room exactly like the engine (hi‑res bytes) and convert to PNG |
| `ro_extract.py` | extract everything (see below) |
| `ro_verify.py` | run the original drawing routines on the emulator and compare with `ro_render` |
| `ro_timing.py` | run the main loop of a save state on the emulator and measure cycles per tick |
| `ro_symbols.sh`, `ro_symbols.swift` | build the app's symbol maps (`RobotOdyssey/Symbols`, Docs/Symbols.md) with a writer: the Mariani/AppleWin symbol files, or with `--code` the MD5 of every mapped routine's code in every world on the given disks (to map a new routine) |
| `ro_mariani.sh` | run once: links the `.sym` files into Mariani's program folder (`RobotOdyssey.sym` also as `A2_USER1.SYM`, loaded at start‑up) and writes a `DebuggerAutoRun.txt` (Docs/Symbols.md, *Symbol files*) |
| `ro_chips.py` | find the chips (program disks: the loaders' set‑up; save state; storage disk: every saved game) and disassemble them |
| `ro_chip_disasm.py` | Micah Dowty's chip disassembler (PC CHP/CSV files, same bytecode as the Apple II; MIT licence, ported to Python 3) |
| `native_check.sh`, `native_check.swift` | build the app's engine sources with a checker and compare the native routines with the original 6502 code: every room's draw phase with and without them, every world's main loop tick by tick (without input – also with the natives switched on and off at random mid‑tick –, and 300 ticks with the same keys, joystick moves and buttons fed to both), and direct calls on random robot states and on random objects, moves, walls, keys and joystick positions (memory byte for byte; registers and flags too for the object motion and input routines); fails too where a world's engine code doesn't match the symbols' fingerprints |
| `ro_sounds.sh`, `ro_sounds.swift` | build the app's sources with a sound tool: every world's sound table by name against the sound map (`GameSounds`), every sound of the map run by the original PLAY_SOUNDS and by the native one (cycles and speaker clicks must match), with `--wav DIR` as WAV files rendered like the app (`SpeakerRenderer`); Docs/Sound.md |
| `loader_check.sh`, `loader_check.swift` | build the app's sources with a checker that drives the original loader headless (`Loader`, `DiskDrive`, `GameLoop`) with keys: levels 1‑4's exit code and the next level arriving and running, Level 1 saved on a new storage disk (the slot read back must hold the world as it was), the menu and its five worlds (chosen with ↓), Esc in the menu (its tune, Robotropolis then without its intro), Robotropolis with PLAY_INTRO switched off (the intro plays, its tunes streamed 1/60 s at a time as the viewer does must equal each tune rendered at once), the menu natives (DRAW_PICTURE, XOR_BLOCK) call by call against the original in the menu, the title and the intro, Level 1's sounds run and streamed as the viewer does with PLAY_SOUNDS native and switched off (alike, no pause the original doesn't have, no click where the player runs dry), the walls easter egg (Ctrl‑A Ctrl‑L T, then Ctrl‑E), the saved game restored from the menu (equal to `WorldBuilder`'s after one tick but for the loader's own bytes), a new storage disk made with *C*; `--png DIR` writes the screens on the way (Docs/Loader.md) |
| `ro_map.sh`, `ro_map.swift` | build the app's sources with a map printer: for every world on the disks the map of the *Map* view (`WorldMap`) as text, with the player's room in brackets, how many exits it shows as rooms next door, the time it took, and the exits left as badges; paths must be absolute (the script runs in `Data/`) |
| `mouse_check.sh`, `mouse_check.swift` | build the app's engine sources with a checker for the Mac's mouse as the game's (`AppleMouse`, the mouse card in slot 4), headless, in Level 1 and every kit and lab world: the card in where a tick starts (INPUT_DEVICE 2, SLOT_POINTER, its ROM, the game's own set-up with its CLAMPMOUSE), the mouse moved 3 right (the player 3), 30 right (7, the rest lost), 30 up (15), K typed with the card in (7 right), the card out (INPUT_DEVICE, SLOT_POINTER and the ROM page as before); the player put on a free pin (a room without a chip), the pen taken with S, a click (a wire started), walked by the mouse to a pin of the other type and a click (the wire made), pressed on a free pin for 3 ticks with the mouse wobbling (one press: the wire still being made), a click on a wired pin and one held for 4 ticks (the wire cut, no new one started); in Level 1 gate $25 taken with a click and moved 7 by the mouse (its wires with it) (Frontends.md "Input") |
| `layer_check.sh`, `layer_check.swift` | build the app's engine sources with a checker for the canvas's layers of the pages (`PageLayers`, `Machine.layers`), headless, in every world: keeping them and not the same memory, bank 1 and page after every tick (keys typed, the help), and what keeping them costs; every room drawn with the layers (natives on, and all 6502 code) against the page the 6502 code draws with every write inside the layer's routines (the natives with `Native.Flags.drawsOnLayer3`: texts, sprites, plots, lines) undone – layer 2 differs only in bytes they drew in (bits set again by later drawing: counted, 0), the canvas's Apple pixels (`LayerPixels`: layer 2 with layer 3's sprites, plots and lines and the writes between them, in order) the page but for the letters' cells with every routine on and with DRAW_SPRITE, the plots and lines, or both switched off, the loop's page on screen with the same layers, the room's texts all there, the letters as the canvas draws them (`DrawnText.characters`) never two in one cell but in room $3F (accents merged: Level 2's "Musé"); `?` – the help page drawn outside the draw phase: layer 2 the page without its letters (Frontends.md "The native layer") |
| `ro_dump.sh`, `ro_dump.swift` | build the app's world sources with a dumper: every world's memory as its main loop starts (after its start-up code, the language card pieces in), `DIR/<id>.main.bin` (64K, bank 2 at $D000) and `<id>.bank1.bin`, to disassemble with `dis6502.py` (Apple2Kit's `Data/`) (the kit's and the lab's pieces at $D000/$F000 aren't in `ro_world.py`'s images) |
| `cpu6502.py` | small NMOS 6502 emulator for the Python tools (documented opcodes, cycle counting); the app's CPU is the `MOS6502` package |
| `packages.sh` | sourced by the `.sh` scripts that build Swift: compiles the packages the app uses, `MOS6502` and Apple2Kit's emulator core, into modules and sets `$PACKAGES` (swiftc flags). Sources: `$MOS6502_PACKAGE`/`$APPLE2KIT_PACKAGE`, else the working copies beside this project (`../../MOS6502`, `../../Apple2Kit`), else GitHub clones (`$MOS6502_REF`, default 1.0.0; `$APPLE2KIT_REF`, default main) |
| `apple2kit_data.py` | imported by the Python tools that use `dis6502.py`/`hires.py`: those live in Apple2Kit's `Data/` (with `hexdump.py`; `$APPLE2KIT_PACKAGE`, else `../../Apple2Kit`) |
| `aws_state.py` | extract main/aux RAM from a Mariani/AppleWin `.yaml` save state |
| `ro_title.py` | unpack the title pictures like the menu ($0A71) and write the three title screens; `--verify` compares with the original unpacker and wipe on the emulator (format: `Docs/DiskLayout.md`, *Title pictures*) |
| `ro_icon.py` | the app icon: robot 2, Scanner (the blue one), drawn by the engine ($9D18, $D2BC) from the save state, 20× on a dark background, all macOS sizes |
| `ro_shuffle.py` | Level 1's shuffled black crystal (L1_SHUFFLE_OBJECTS, Docs/Engine.md): its six maze spots drawn like the engine, the crystal in white, in one PNG (`Docs/crystal_spots.png`) |

## Extracted/v1.1

| File | Contents |
|---|---|
| `<world>.bin` | world image $6000‑$94FF (0x3500 bytes) |
| `<world>.code.bin` | $0800‑$1FFF: the world's own 6502 code |
| `<world>.json` | rooms (walls, links, colours, objects, texts; `code` for rooms holding 6502 code), all objects (with wires), all texts, robots |
| `<world>.png` | all 64 rooms; room *n* at column *n*%8, row *n*/8 |
| `<world>/room_NN.png` | single rooms (with `--rooms`) |
| `font.bin` | 8 glyph rows × 96 characters ($A0‑$FF), row 0 = bottom, bit 0 = left |
| `colors.bin` | 32 colours × 4 pattern bytes |
| `title_1..3.png`, `.bin` | the title screens: “The Learning Company presents”, the Robot Odyssey title, the menu frame (8K hi‑res page each) |
| `chips.txt` | disassembled chips of Level 1 and the Innovation Lab Tutorial (`ro_chips.py "$A" "$B" > …`) |

Worlds: `level1`‑`level5`, `anatomy` (Robot Anatomy), `toolkit`,
`labtutorial` (Innovation Lab Tutorial), `lab` (Innovation Lab).
Levels 2‑5 show the state when entered from an untouched previous level.

The `.bin` files are raw data from the game disks and are not committed
(`.gitignore`); `ro_extract.py` and `ro_title.py` write them.

## Mariani symbol files

Written by `ro_symbols.sh` from the app's symbol maps, so the names are the
Swift names in capitals (`currentRoom` is `CURRENT_ROOM`).

`RobotOdyssey.sym` – the Robotropolis levels, v1.1: engine routines and
variables, the world tables (`OBJ_ROOM`, `ROOM_WALLS`, `TEXT_POINTER_LOW`, …)
and the Level 1 code (`L1_…`, including `L1_MAIN_LOOP` = $0841, one
iteration per tick). `RobotOdyssey_v1.0.sym` – the same for v1.0 (some
$D000 routines a few bytes later). `RobotOdysseyKit.sym`,
`RobotOdysseyLab.sym` – Robot Anatomy/Toolkit and the Innovation Lab worlds.
`RobotOdysseyLoader.sym` – boot loader, file loader (`LOAD_FILES` $4A20),
menu and save/restore at $4000‑$5DFF. Keep it separate: during play that
area is hi‑res page 2, and loader names there would mislabel screen writes.
Names ending in `_Q` are guesses. Add names to `RobotOdyssey/Symbols` and
rerun `ro_symbols.sh`. For Mariani's debugger run `ro_mariani.sh` once
(Docs/Symbols.md, *Symbol files*).
