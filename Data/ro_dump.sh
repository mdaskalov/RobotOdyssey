#!/bin/sh
# Builds ro_dump.swift with the app's world sources and runs it.
# Usage: ./ro_dump.sh DIR DISK.dsk...   (paths absolute or from Data/)
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_dump"
. ./mos6502.sh
swiftc -O -wmo -parse-as-library $MOS6502 -o "$OUT" ro_dump.swift \
    $APP/Engine/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
