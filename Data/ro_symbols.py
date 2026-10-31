#!/usr/bin/env python3
"""Write AppleWin/Mariani symbol files for Robot Odyssey I (v1.1).

Usage: ro_symbols.py [OUTDIR]   (default: this directory)

RobotOdyssey.sym        engine, world tables, Level 1 code ($0803-$18FF)
RobotOdysseyLoader.sym  boot/menu loader on track 1 ($4000-$5DFF), which is
                        hi-res page 2 while the game runs, so keep it separate.

Names ending in _Q are guesses.  Level code at $0803-$1FFF and $8EF0-$94FF
differs per level; the L1_ names are for Level 1 only.
"""
import sys
from pathlib import Path

GAME = {
    # --- zero page ------------------------------------------------------
    0x00: "ZP_PTR", 0x0A: "ZP_TEXTPTR", 0x0D: "ZP_SPRITEPTR", 0x0F: "ZP_PAT_EVEN", 0x10: "ZP_PAT_ODD",
    0x14: "ZP_DRAW_Y", 0x16: "ZP_LINE_HI_PTR", 0x18: "ZP_DRAW_X", 0x19: "ZP_JUMP_VEC",

    # --- level code (Level 1) -------------------------------------------
    0x0803: "LEVEL_START", 0x0806: "LEVEL_SOUND_Q", 0x0816: "LEVEL_INIT",
    0x0841: "MAIN_LOOP", 0x091C: "MAIN_LOOP_END",
    0x0920: "L1_HELD_CHANGED_Q", 0x0963: "L1_KEY_COMMANDS",
    0x0A07: "L1_SHOW_TEXT_ROOM", 0x0A77: "L1_WAIT_KEY",
    0x0A83: "L1_EXIT_NEXT_LEVEL", 0x0A8E: "L1_EXIT_MODE5", 0x0A99: "L1_EXIT_MENU", 0x0AA1: "L1_EXIT_MODE4",
    0x0AAC: "L1_EXIT_TO_LOADER",
    0x0B7B: "L1_EXIT_OBJ_TBL", 0x0B81: "L1_EXIT_ROOM_TBL", 0x0B87: "L1_EXIT_X_TBL", 0x0B8D: "L1_EXIT_Y_TBL",
    0x0B93: "L1_EXIT_SCRIPT",
    0x0C06: "L1_TICK_0C06", 0x0CA8: "L1_TICK_0CA8", 0x0F93: "L1_TICK_0F93", 0x101A: "L1_ROOM2A_Q",
    0x10F8: "L1_WELCOME_ROOM_Q", 0x1305: "L1_TICK_1305", 0x1740: "L1_TICK_1740", 0x187C: "L1_ROOM03_1F_Q",

    # --- shared engine pieces ---------------------------------------------
    0x1A50: "KEY_T_HANDLER", 0x1AB0: "ENG_1AB0", 0x1DB6: "ENG_1DB6", 0x1DE1: "FORMAT_NUMBERS",
    0x1E3B: "ENG_1E3B",

    # --- world: objects ($6000-$69FF, 256 entries per array) --------------
    0x6000: "OBJ_NEXT", 0x6100: "OBJ_SPRITE", 0x6200: "OBJ_COLOR", 0x6300: "OBJ_ROOM",
    0x6400: "OBJ_X", 0x6500: "OBJ_Y", 0x6600: "OBJ_LINK", 0x6700: "OBJ_LINK_DX", 0x6800: "OBJ_LINK_DY",
    0x6900: "OBJ_FLAGS", 0x6A00: "SPRITES",
    # rooms ($6E00-$6FFF, 64 entries per array)
    0x6E00: "ROOM_FIRST_OBJ", 0x6E40: "ROOM_FLOOR_COLOR", 0x6E80: "ROOM_WALL_COLOR",
    0x6EC0: "ROOM_UP", 0x6F00: "ROOM_DOWN", 0x6F40: "ROOM_RIGHT", 0x6F80: "ROOM_LEFT", 0x6FC0: "ROOM_UNUSED",
    0x7000: "ROOM_WALLS", 0x7780: "WORLD_7780_Q",
    # texts ($7880-$7C7F, 128 entries per array)
    0x7880: "TEXT_ROOM", 0x7900: "TEXT_X", 0x7980: "TEXT_Y", 0x7A00: "TEXT_STYLE", 0x7A80: "TEXT_UNUSED",
    0x7B00: "TEXT_COLOR", 0x7B80: "TEXT_PTR_LO", 0x7C00: "TEXT_PTR_HI", 0x7C80: "TEXT_STRINGS",
    # robots, circuits
    0x8200: "ROBOT_OBJ", 0x8204: "ROBOT_ROOM",
    0x861C: "WIRE_TO", 0x871C: "WIRE_AX", 0x881C: "WIRE_BX", 0x891C: "WIRE_AY", 0x8A1C: "WIRE_BY",
    0x8A82: "PIN_LINE_Q", 0x8CB7: "GATE_TYPE_Q",
    0x8DAA: "TOOL_MODE_Q", 0x8DAB: "MODE_8DAB_Q", 0x8E3E: "GRAB_STATE_Q", 0x8E95: "PLAYER_ROBOT_Q",
    0x8ED6: "TMP_INDEX", 0x8ED8: "FLAG_8ED8_Q",
    # robot state (levels; Docs/Robots.md): 4 grabber bytes per robot, then $1A bytes per robot
    0x8DBD: "ROBOT_GRABBERS", 0x8DCD: "ROBOT_STATE", 0x8DD9: "ROBOT0_THRUSTERS", 0x8DDD: "ROBOT0_BUMPERS",
    0x8DE5: "ROBOT0_BATTERY", 0x8DE6: "ROBOT0_SWITCH",
    # variables and tables of the robot drawing code
    0x8E7E: "RD_GRABBERS", 0x8E82: "RD_PART_INDEX", 0x8E96: "RD_ANTENNA_SIGNAL", 0x8E97: "RD_ANTENNA_COLOR",
    0x8E98: "RD_SCAN_POS", 0x8E99: "RD_SPARK_TOGGLE", 0x8E9A: "RD_RAINBOW_COLOR", 0x8E9B: "RD_RAINBOW_STEP",
    0x8E9C: "RD_RAINBOW_X", 0x8E9D: "RD_RAINBOW_BIT", 0x8E9E: "RD_PULSE_PHASE", 0x8E9F: "RD_RAINBOW_ROW",
    0x8EA0: "RD_RAINBOW_BITS", 0x8EA1: "RD_MODULUS", 0x8EA2: "RD_LOOP", 0x8EB2: "RD_BUMPERS",
    0x8EB6: "RD_THRUSTERS", 0x8EBE: "RD_SWITCH", 0x8EBF: "RD_X", 0x8EC0: "RD_Y", 0x8EC4: "RD_BATTERY_ROWS",
    0x8ED4: "RD_BATTERY",
    0x82D7: "RD_GRABBER_DX", 0x82DB: "RD_GRABBER_DY", 0x831B: "RD_SCAN_DX", 0x8329: "RD_SPARK_DX",
    0x832C: "RD_SPARK_DY", 0x8331: "RD_PULSE_START", 0x8334: "RD_PULSE_COLORS", 0x833D: "RD_PART_LO",
    0x8347: "RD_PART_HI", 0x8351: "RD_PART_X", 0x835B: "RD_PART_Y", 0x836D: "RD_FLAME_PTRS",
    0x8385: "RD_FLAME_DX", 0x8389: "RD_FLAME_DY", 0x84C4: "SPR_DOT", 0x84D4: "SPR_BLANK",
    0x84E4: "SPR_SQUARES", 0x8514: "SPR_SPARKS", 0x8534: "SPR_WINDOW", 0x8544: "SPR_ANTENNA", 0x8554: "SPR_SIGNAL",
    0x8EF0: "LEVEL_DATA", 0x8F69: "L1_ANIMATE_CREATURES",

    # --- engine main ($9500-$B8FF) ----------------------------------------
    0x9460: "FONT_BASE", 0x9500: "FONT",
    0x9839: "LINE_LO_TABLE", 0x9A79: "X_SHIFT_TABLE", 0x9B05: "X_BYTE_TABLE",
    0x9B91: "COLOR_PAT0", 0x9BB1: "COLOR_PAT1", 0x9BD1: "COLOR_PAT2", 0x9BF1: "COLOR_PAT3",
    0x9C34: "LINE_COLOR", 0x9C35: "LINE_X1", 0x9C36: "LINE_Y1", 0x9C37: "LINE_X2", 0x9C38: "LINE_Y2",
    0x9C22: "MOVE_DX", 0x9C23: "MOVE_DY", 0x9C26: "HELD_OBJECT", 0x9C27: "HELD_9C27_Q",
    0x9C2D: "CUR_ROOM", 0x9C2E: "DEST_ROOM", 0x9C2F: "CUR_OBJECT",
    0x9C3B: "BUTTON_A_Q", 0x9C3C: "BUTTON_B_Q", 0x9C3D: "LAST_KEY",
    0x9C3F: "TILE_FLOOR_PAT", 0x9C43: "TILE_WALL_PAT", 0x9C47: "DRAW_PAGE",
    0x9C48: "TEXT_PTR", 0x9C4A: "TXT_STYLE", 0x9C4B: "TXT_COLOR", 0x9C4C: "TXT_X", 0x9C4D: "TXT_Y",
    0x9C52: "LINK_INDEX",
    0x9C53: "MOVE_LINKED_OBJECTS", 0x9C88: "FOLLOW_LINK", 0x9CA1: "GFX_INIT",
    0x9CC3: "DRAW_SPRITE_COLOR", 0x9CD0: "SET_TILE_COLORS",
    0x9D03: "DRAW_ROOM_TILES", 0x9D18: "DRAW_ROOM_OBJECTS", 0x9D56: "ROOM_WALLS_PTR",
    0x9D8F: "SPRITE_PTR", 0x9DB3: "MOVE_OBJECT", 0x9DB9: "MOVE_OBJECT_XY", 0x9E07: "SET_OBJECT_ROOM",
    0x9F13: "PLAY_SOUND_Q", 0x9F3C: "SOUND_TOGGLE_KEY",
    0x9FC4: "VLINE", 0xA04C: "HLINE", 0xA14D: "PLOT", 0xA281: "DRAW_BOX",
    0xA2A2: "DRAW_ROOM_TEXTS", 0xA2EA: "DRAW_TEXT", 0xA3AB: "TEXT_LINE_ADDR", 0xA3E1: "DRAW_BIG_TEXT",
    0xA4B9: "BIG_TEXT_PAT_EVEN", 0xA4C1: "BIG_TEXT_PAT_ODD", 0xA4C9: "BIT_REVERSE_TABLE",
    0xA5CD: "BUTTON_EDGES_Q", 0xA6AD: "ENG_A6AD", 0xA90C: "READ_INPUT_Q", 0xAC24: "ENG_AC24",
    0xAEEB: "DRAW_VECTOR", 0xAEED: "FLIP_PAGE", 0xAF1C: "DRAW_INDIRECT", 0xAF1F: "DRAW_SPRITE",
    0xB2A5: "MASK_HI_TABLE", 0xB37C: "MASK_LO_TABLE", 0xB496: "TILE_PATTERNS", 0xB4A2: "LOAD_TILE_PATTERNS",
    0xB4DF: "FILL_TILE", 0xB8E6: "ENG_B8E6", 0xB8ED: "ENG_B8ED",

    # --- language card ($D000-$FFFF, bank 2 code) --------------------------
    0xD000: "ROBOTS_RESET_Q", 0xD2BC: "DRAW_ROBOTS", 0xD2C8: "DRAW_ROBOT2_SCAN", 0xD359: "DRAW_ROBOT1_SPARKS",
    0xD3F5: "SPARK_POSITION", 0xD414: "RANDOM_BELOW_A", 0xD429: "RANDOM", 0xD434: "RANDOM_STEP",
    0xD442: "DRAW_BLANK", 0xD44D: "DRAW_ROBOT0_RAINBOW", 0xD4CC: "DRAW_ROBOT3_PULSE", 0xD573: "DRAW_ROBOT_PARTS",
    0xD6AB: "DRAW_RAINBOW", 0xD72B: "DRAW_ROBOT_INTERIOR", 0xD783: "DRAW_BATTERY", 0xD7D0: "DRAW_INTERIOR_PARTS",
    0xD832: "ROBOTS_THRUSTERS_Q", 0xDA44: "ENG_DA44", 0xDA90: "ENG_DA90",
    0xDD59: "PLAYER_IN_ROBOT", 0xDDD0: "ENG_DDD0", 0xDE10: "ROBOTS_4_UPDATE_Q",
    0xDE95: "CRYSTALS_Q", 0xDF81: "CRYSTALS2_Q", 0xDFA3: "PLAYER_MOVE_Q",
    0xF04B: "GATES_EVAL_Q", 0xF0CC: "WIRES_PROPAGATE", 0xF44D: "SENSORS_Q", 0xF56B: "CHIPS_EVAL_Q",
    0xF5A9: "ENG_F5A9", 0xF5C2: "REMOTE_CONTROL_Q", 0xF7BE: "ENG_F7BE",
    0xFC62: "DRAW_WIRES", 0xFE18: "SAVE_MOVE_DELTA", 0xFE25: "ENG_FE25",
    0xBDE1: "GRAB_LOGIC_Q", 0xBEBC: "GRAB_BUTTON_Q", 0xBED6: "ENG_BED6",

    # --- I/O -----------------------------------------------------------------
    0x02D0: "MENU_MODE", 0x02D1: "NEXT_LEVEL", 0x02D2: "WORLD_INDEX", 0x03F2: "RESET_VECTOR",
}

LOADER = {
    0x4000: "LOADER_START", 0x4003: "LOADER_RESTART", 0x4040: "MENU_DISPATCH",
    0x40B9: "LOAD_LEVEL2", 0x40C5: "LOAD_LEVEL3", 0x40D1: "LOAD_LEVEL4", 0x40DD: "LOAD_LEVEL5",
    0x40E9: "LOAD_ENDING_Q", 0x4193: "SAVE_GAME_WRITE", 0x435E: "RESTORE_LOAD_CODE",
    0x437E: "LOAD_CODE_L1", 0x4386: "LOAD_CODE_L2", 0x438E: "LOAD_CODE_L3", 0x4396: "LOAD_CODE_L4",
    0x439E: "LOAD_CODE_L5", 0x43A6: "LOAD_CODE_LAB", 0x443A: "RESTORE_GAME",
    0x44B0: "JUMP_AY", 0x456C: "START_WORLD",
    0x4582: "LOAD_ENGINE", 0x4595: "LOAD_LEVEL1", 0x45C4: "LOAD_LAB", 0x45E2: "LOAD_ANATOMY",
    0x45F8: "LOAD_TOOLKIT", 0x460E: "LOAD_LAB_TUTORIAL",
    0x4A20: "LOAD_FILES", 0x4B80: "CHECK_DISK_SIDE", 0x4B9C: "READ_SIDE_ID", 0x4DC4: "FILE_TABLE",
    0x4F00: "BOOT2", 0x59E8: "RWTS_IOB", 0x5A00: "RWTS", 0x5CB8: "RWTS_SKEW", 0x5D00: "BOOT2_ENTRY",
}


def write_sym(path, title, symbols):
    lines = [f"; {title}", "; Robot Odyssey I (Apple II) v1.1 - generated by Data/ro_symbols.py",
             "; Names ending in _Q are guesses; L1_ names apply to Level 1 code only.", ""]
    for addr, name in sorted(symbols.items(), key=lambda kv: kv[1]):
        lines.append(f"{addr:4X} {name}" if addr < 0x100 else f"{addr:04X} {name}")
    Path(path).write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
    write_sym(out / "RobotOdyssey.sym", "Robot Odyssey game symbols", GAME)
    write_sym(out / "RobotOdysseyLoader.sym", "Robot Odyssey boot/menu loader symbols", LOADER)
    print(f"wrote {len(GAME)} + {len(LOADER)} symbols to {out}")


if __name__ == "__main__":
    main()
