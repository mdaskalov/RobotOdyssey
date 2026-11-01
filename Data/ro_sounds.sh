#!/bin/sh
# Builds ro_sounds.swift with the app's engine sources and runs it.
# Usage: ./ro_sounds.sh [--wav DIR] DISK.dsk...   (program sides A and B)
set -e
cd "$(dirname "$0")"
APP=../RobotOddyssey
OUT="${TMPDIR:-/tmp}/ro_sounds"
swiftc -O -wmo -parse-as-library -o "$OUT" ro_sounds.swift \
    $APP/Emulation/CPU6502.swift $APP/Engine/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift $APP/Rendering/SpeakerRenderer.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
