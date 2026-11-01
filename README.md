# Robot Odyssey

A macOS recreation of [Robot Odyssey](https://en.wikipedia.org/wiki/Robot_Odyssey),
the 1984 Apple II game by The Learning Company where you build circuits inside
robots to escape Robotropolis.

As a kid, this game was one of my favorites, as it was for many like me.
Back then I even skipped school for a few days to figure out how it works.
With a modified ROM that let me break into the game and debug it, I found out
how the rooms and the joined objects work.

Forty years later I came back to finish the job. I took the original disks
apart with an emulator ([Mariani](https://github.com/sh95014/AppleWin)) to step
through the 6502 code, a pile of small [scripts](Data/README.md) to pull out
the files, worlds, sprites and sounds, and a lot of help from
[Claude Code](https://claude.com/claude-code).

Routine by routine, in just two days, we worked out the world format, the
engine, the sound and the loader. This app is the result: the original game,
rebuilt in Swift and running just as it did on the Apple II.

## How it works

The goal is to recreate the game as precisely as possible, straight from the
original disks. The world and level code runs unchanged on a built-in 6502
emulator, tick by tick at the original speed, so every circuit behaves as it
did on the Apple. Engine routines are ported to Swift one by one, and each one
is checked byte for byte against the original. The loader and the menu run as
well, so you can change levels and save and load games.

## Running it

Open `RobotOdyssey.xcodeproj` in Xcode and run. The original disk images are
not included. Put your own dump in `RobotOdyssey/Resources/` as `diskA.dsk`
and `diskB.dsk`. Both v1.0 and v1.1 work; v2.0 is not supported (yet).

## Plans

I also plan to make an Apple TV version, to play it on the big screen.

## Docs

The reverse engineering notes on the disks, the world format, the engine, the
sound and the loader are in [Docs](Docs/README.md).
