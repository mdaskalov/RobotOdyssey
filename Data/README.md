# Data – tools and extracted data

Python 3 scripts, no dependencies. Run them from this folder.

```sh
A="/Volumes/SSD/Apple II/Robot Oddisey/Ro1v11a.dsk"
B="/Volumes/SSD/Apple II/Robot Oddisey/Ro1v11b.dsk"
STATE="/Volumes/SSD/Apple II/Robot Oddisey/RO_L1_SaveState.yaml"

python3 ro_extract.py "$A" "$B" Extracted/v1.1 [--rooms]   # all worlds -> bin/json/png
python3 ro_verify.py "$STATE"        # renderer vs. the original drawing code: 64/64 rooms identical
python3 ro_timing.py "$STATE" 20     # cycles per tick of the Level 1 main loop
python3 ro_symbols.py                # writes RobotOdyssey.sym and RobotOdysseyLoader.sym
python3 ro_chips.py "$A" "$B"        # disassemble the chips (also: STATE.yaml or a STORAGE.dsk)
./native_check.sh "$A" "$B" [STORAGE.dsk]   # native Swift routines vs. the original code
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
| `ro_symbols.py` | generate the Mariani/AppleWin symbol files |
| `ro_chips.py` | find the chips (program disks: the loaders' set‑up; save state; storage disk: every saved game) and disassemble them |
| `ro_chip_disasm.py` | Micah Dowty's chip disassembler (PC CHP/CSV files, same bytecode as the Apple II; MIT licence, ported to Python 3) |
| `native_check.sh`, `native_check.swift` | build the app's engine sources with a checker and compare the native routines with the original 6502 code: every room's draw phase with and without them, every world's main loop tick by tick, and direct calls on random robot states (memory byte for byte) |
| `cpu6502.py` | NMOS 6502 emulator with cycle counting (the Swift `CPU6502` mirrors it) |
| `dis6502.py` | small disassembler: `dis6502.py FILE START END [BASE]` |
| `hexdump.py` | hex dump with Apple text column: `hexdump.py FILE START END [BASE]` |
| `aws_state.py` | extract main/aux RAM from a Mariani/AppleWin `.yaml` save state |
| `hires.py` | hi‑res address mapping, simple PNG writer and screen dump: `hires.py MEM.bin OUT.png [2000]` |

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
| `chips.txt` | disassembled chips of Level 1 and the Innovation Lab Tutorial (`ro_chips.py "$A" "$B" > …`) |

Worlds: `level1`‑`level5`, `anatomy` (Robot Anatomy), `toolkit`,
`labtutorial` (Innovation Lab Tutorial), `lab` (Innovation Lab).
Levels 2‑5 show the state when entered from an untouched previous level.

This is data from the game disks – keep it out of public repositories.

## Mariani symbol files

`RobotOdyssey.sym` – engine routines and variables, the world tables
(`OBJ_ROOM`, `ROOM_WALLS`, `TEXT_PTR_LO`, …) and the Level 1 code (`L1_…`,
including `MAIN_LOOP` = $0841, one iteration per tick).
`RobotOdysseyLoader.sym` – boot loader, file loader (`LOAD_FILES` $4A20),
menu and save/restore at $4000‑$5DFF. Keep it separate: during play that
area is hi‑res page 2, and loader names there would mislabel screen writes.
Names ending in `_Q` are guesses. Edit `ro_symbols.py` and rerun it to add more.
