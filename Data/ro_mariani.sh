#!/bin/sh
# Sets up Mariani's debugger for the .sym files; run it once (Docs/Symbols.md,
# Symbol files). In Mariani's program folder (~/Library/Application Support/
# <bundle id>/) it links the five .sym files by name (SYMUSER LOAD "name"),
# RobotOdyssey.sym as A2_USER1.SYM (loaded when the emulator starts), and
# writes a DebuggerAutoRun.txt: the loader's names in User 2, off, and
# Applesoft's names off. The links follow what ro_symbols.sh writes.
# Usage: ./ro_mariani.sh [path/to/Mariani.app]
set -e
cd "$(dirname "$0")"
DATA="$PWD"

APP="$1"
if [ -z "$APP" ]; then
    for a in /Applications/Mariani.app "$HOME/Applications/Mariani.app"; do
        if [ -d "$a" ]; then APP="$a"; break; fi
    done
fi
if [ -n "$APP" ]; then
    ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist")
else
    ID=com.applewin.marianipro
    echo "Mariani.app not found, taking $ID (give the app's path to use another)"
fi
DIR="$HOME/Library/Application Support/$ID"
mkdir -p "$DIR"

# a link, but never in place of a file that isn't one
link() {
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        echo "kept $2 (not a link)"
    else
        ln -sf "$1" "$2"
        echo "$2 -> $1"
    fi
}

for f in RobotOdyssey RobotOdyssey_v1.0 RobotOdysseyKit RobotOdysseyLab RobotOdysseyLoader; do
    link "$DATA/$f.sym" "$DIR/$f.sym"
done
link "$DATA/RobotOdyssey.sym" "$DIR/A2_USER1.SYM"

AUTORUN="$DIR/DebuggerAutoRun.txt"
if [ -e "$AUTORUN" ]; then
    echo "kept $AUTORUN"
else
    printf '%s\n' 'SYMUSER2 LOAD "RobotOdysseyLoader.sym"' 'SYMUSER2 OFF' 'SYMBASIC OFF' > "$AUTORUN"
    echo "wrote $AUTORUN"
fi
echo "Restart Mariani to load the symbols."
