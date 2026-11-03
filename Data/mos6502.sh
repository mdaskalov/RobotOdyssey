# Sourced by the scripts that build Swift (from Data/): compiles the MOS6502
# package (../Packages/MOS6502) into a module and a static library and sets
# MOS6502 to the swiftc flags that use it.
MOS6502_OUT="${TMPDIR:-/tmp}/ro_mos6502"
mkdir -p "$MOS6502_OUT"
swiftc -O -wmo -parse-as-library -cross-module-optimization -module-name MOS6502 \
    -emit-module -emit-module-path "$MOS6502_OUT/MOS6502.swiftmodule" \
    -emit-library -static -o "$MOS6502_OUT/libMOS6502.a" ../Packages/MOS6502/Sources/MOS6502/*.swift
MOS6502="-I $MOS6502_OUT -L $MOS6502_OUT -lMOS6502"
