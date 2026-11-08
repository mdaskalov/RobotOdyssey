#!/bin/sh
# Builds ro_symbols.swift with the app's symbol maps and runs it.
# Usage: ./ro_symbols.sh [OUTDIR]               write the .sym files
#        ./ro_symbols.sh --code DISK.dsk...     the routines' fingerprints on the disks
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_symbols"
. ./packages.sh
swiftc -O -wmo -parse-as-library $PACKAGES -o "$OUT" ro_symbols.swift \
    $APP/Engine/*.swift $APP/Natives/*.swift $APP/Symbols/*.swift $APP/Rendering/RoomRenderer.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
