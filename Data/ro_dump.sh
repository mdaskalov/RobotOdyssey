#!/bin/sh
# Builds ro_dump.swift with the app's world sources and runs it.
# Usage: ./ro_dump.sh DIR DISK.dsk...   (paths absolute or from Data/)
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_dump"
. ./packages.sh
swiftc -O -wmo -parse-as-library $PACKAGES -o "$OUT" ro_dump.swift \
    $APP/Engine/*.swift $APP/Natives/*.swift $APP/Symbols/*.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
