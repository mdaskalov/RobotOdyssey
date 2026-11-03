#!/bin/sh
# Builds ro_map.swift with the app's world sources and runs it.
# Usage: ./ro_map.sh DISK.dsk...   (program sides A and B)
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_map"
. ./mos6502.sh
swiftc -O -wmo -parse-as-library $MOS6502 -o "$OUT" ro_map.swift \
    $APP/Engine/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift $APP/Rendering/SpeakerRenderer.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift $APP/Model/WorldMap.swift
"$OUT" "$@"
