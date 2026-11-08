# Sourced by the scripts that build Swift (from Data/): compiles the packages
# the app uses into modules and static libraries and sets PACKAGES to the
# swiftc flags that use them: MOS6502 and Apple2Kit's emulator core
# (Sources/Apple2Kit/Emulator; its UI needs SwiftUI and stays out).
# Each package's sources: $MOS6502_PACKAGE / $APPLE2KIT_PACKAGE if set (a
# working copy), else the working copy beside this project (../MOS6502,
# ../Apple2Kit, as the Xcode project takes Apple2Kit), else a clone of
# $MOS6502_REF / $APPLE2KIT_REF (a tag or branch) kept in $TMPDIR.
PACKAGES_OUT="${TMPDIR:-/tmp}/ro_packages"
mkdir -p "$PACKAGES_OUT"

# package_source NAME URL REF: the sources' folder of package NAME.
package_source() {
    if [ -d "../../$1/Sources" ]; then
        (cd "../../$1" && pwd)
        return
    fi
    dir="$PACKAGES_OUT/src-$1-$3"
    if [ ! -d "$dir/.git" ]; then
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$3" "$2" "$dir" >&2
    elif ! git -C "$dir" describe --tags --exact-match >/dev/null 2>&1; then
        git -C "$dir" pull --quiet --ff-only >&2     # a branch: bring it up to date
    fi
    echo "$dir"
}

MOS6502_PACKAGE="${MOS6502_PACKAGE:-$(package_source MOS6502 https://github.com/mdaskalov/MOS6502.git "${MOS6502_REF:-1.0.0}")}"
APPLE2KIT_PACKAGE="${APPLE2KIT_PACKAGE:-$(package_source Apple2Kit https://github.com/mdaskalov/Apple2Kit.git "${APPLE2KIT_REF:-main}")}"
export APPLE2KIT_PACKAGE                         # the Python tools take dis6502/hires from its Data/

swiftc -O -wmo -parse-as-library -cross-module-optimization -module-name MOS6502 \
    -emit-module -emit-module-path "$PACKAGES_OUT/MOS6502.swiftmodule" \
    -emit-library -static -o "$PACKAGES_OUT/libMOS6502.a" "$MOS6502_PACKAGE"/Sources/MOS6502/*.swift
swiftc -O -wmo -parse-as-library -cross-module-optimization -module-name Apple2Kit \
    -I "$PACKAGES_OUT" \
    -emit-module -emit-module-path "$PACKAGES_OUT/Apple2Kit.swiftmodule" \
    -emit-library -static -o "$PACKAGES_OUT/libApple2Kit.a" "$APPLE2KIT_PACKAGE"/Sources/Apple2Kit/Emulator/*.swift
PACKAGES="-I $PACKAGES_OUT -L $PACKAGES_OUT -lApple2Kit -lMOS6502"
