#!/bin/sh
# Builds loader_check.swift with the app's sources and runs it.
# Usage: ./loader_check.sh [--png DIR] SIDE_A.dsk SIDE_B.dsk
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/loader_check"
swiftc -O -wmo -parse-as-library -o "$OUT" loader_check.swift \
    $APP/Emulation/CPU6502.swift $APP/Engine/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift $APP/Rendering/HiresImage.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
