#!/bin/sh
# Compares the MOS6502 package with AppleWin's 6502: builds AppleWin's own CPU
# code from a checkout (cpu_check_applewin.cpp) and the checker
# (cpu_check.swift), runs random single instructions of every opcode on both.
# Usage: ./cpu_check.sh path/to/AppleWin [CASES_PER_OPCODE]
set -e
cd "$(dirname "$0")"
if [ ! -f "$1/source/CPU/cpu6502.h" ]; then
    echo "usage: $0 path/to/AppleWin [CASES_PER_OPCODE]" >&2
    exit 2
fi
OUT="${TMPDIR:-/tmp}"
. ./mos6502.sh
clang++ -std=c++17 -O2 -w -I "$1/source/CPU" -o "$OUT/ro_cpu_applewin" cpu_check_applewin.cpp
swiftc -O -wmo -parse-as-library $MOS6502 -o "$OUT/ro_cpu_check" cpu_check.swift
"$OUT/ro_cpu_applewin" "$OUT/ro_cpu_cases.bin" "${2:-1000}"
"$OUT/ro_cpu_check" "$OUT/ro_cpu_cases.bin"
