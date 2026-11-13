#!/bin/sh
# Builds native_check.swift with the app's engine sources and runs it.
# Usage: ./native_check.sh DISK.dsk...   (program sides A and B, storage disks)
set -e
cd "$(dirname "$0")"
APP=../RobotOdyssey
OUT="${TMPDIR:-/tmp}/ro_native_check"
. ./packages.sh
swiftc -O -wmo -parse-as-library $PACKAGES -o "$OUT" native_check.swift \
    $APP/Engine/*.swift $APP/Natives/*.swift $APP/Symbols/*.swift \
    $APP/Model/DiskImage.swift $APP/Model/GameCatalog.swift $APP/Model/World.swift $APP/Model/WorldBuilder.swift
"$OUT" "$@"
