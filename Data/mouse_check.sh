#!/bin/sh
# Builds mouse_check.swift with the app's engine sources and runs it.
# Usage: ./mouse_check.sh SIDE_A.dsk SIDE_B.dsk   (paths absolute or from Data/)
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_mouse_check"
. ./mos6502.sh
swiftc -O -wmo -parse-as-library $MOS6502 -o "$OUT" mouse_check.swift \
    $APP/Engine/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
