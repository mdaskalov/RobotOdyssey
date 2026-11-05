# Switches: original against native, Apple against modern – plan

Thoughts (2026‑11‑03); step 1, the switches, is built (below). The idea: switches in
the *Current Room* panel that turn each native routine on or off, and a modern front
end (the Mac drawing over the page, modern sound) beside the Apple's, so every
improvement can be seen next to the original and compared with it.

## What is there already

The machine already works at the level Mariani does: the game sees the
Apple's hardware and the app shows what that hardware puts out.

* **Graphics:** the game draws into the hi‑res pages ($2000/$4000) and
  flips them ($C054/$C055); the viewer shows the page on screen
  (`HiresImage`, colour or mono).
* **Input:** keyboard $C000/$C010, buttons $C061/$C062, paddle timers by
  CPU cycles (`InputDevices`); the Mac's keys and a game controller drive
  them.
* **Sound:** the speaker's clicks ($C030), to the cycle, made into a square
  wave with the speaker's high pass (`SpeakerRenderer`).

What differs from Mariani is only how faithfully the output is shown: the
colours are the four hi‑res colours by palette bit and column parity, not
an NTSC signal. That's a choice for the Apple view (an *NTSC* mode could be
added), not something the switches need.

So nothing has to be emulated anew. What the plan needs is a clean line
between two kinds of change:

| | Engine natives | Front end |
|---|---|---|
| where | inside the tick (6502 entry points) | after the tick, on its output |
| contract | memory byte for byte as the original | free |
| switching it shows | nothing but the pace (natives take no cycles: faster, by design) | the improvement |
| checked by | `native_check`, and a live check (below) | the Apple view beside it |

## Switches for the natives

Built (2026‑11‑03): each native the world's code check allows has a
switch in the *Current Room* panel's *Native routines* list (its entry point beside
it, what it reproduces in its help), and *All* over them (mixed while some
are off); the names switched off are kept in the user defaults
(`ViewerModel.nativesOff`, `nativesOff`) and hold for every world.

* **Any mix is valid.** A native leaves memory (and registers where callers
  use them) as the original does, so the 6502 code and the native can
  replace each other at any call, in any combination. The switches only
  filter what `Machine.install` put in (`Machine.switchedOff`; the traps
  stay, a switched‑off entry runs its 6502 code), and they count from the
  next instruction: a native runs whole within one, so there is no half
  state to wait for. `native_check` runs a third loop with the natives
  switched at random in the middle of every tick against the original.
* **`uses`:** a switch turns off the entry, not the routines a native
  reproduces. With DRAW_SPRITE off, DRAW_ROBOTS (on) still draws its
  sprites in Swift; only the calls to DRAW_SPRITE from 6502 code run the
  original. The list could show the reproduced routines under each native.
* **`CodeCheck` still decides** what may be on: a routine that differs from
  its fingerprint has no switch (greyed, as now).
* **The engine's natives, and the intro.** The loader's natives (boot ROM,
  RWTS, the drive, the copy checks) stand in for hardware and have no 6502
  code to fall back to. PLAY_INTRO, which steps over Robotropolis' intro,
  has: its switch (under *Loader*, outside *All*) lets the intro play. So
  do the menu's drawing natives, DRAW_PICTURE and XOR_BLOCK (under
  *Loader*).
* **Sound with PLAY_SOUNDS off:** the 6502 loops click $C030 themselves;
  `Machine` records every click in the game too, and the viewer streams
  them to the cycle (Sound.md, *The stream*), so the two can be heard one
  after the other. The tick runs ahead through the 6502 sound as the
  native takes its cycles (`GameLoop.run`), so they sound alike.
* **Pace.** Natives take no cycles (except PLAY_SOUNDS), so turning them on
  makes a tick shorter and *Authentic* pacing faster (READ_INPUT's paddle
  loop alone is about 3,000 cycles; a robot room 6.6 ticks/s against 4.5
  with all off). That is the point of them (the user, 2026‑11‑03): the
  original slows down with many objects in a room. What a tick does stays
  the original's – movement, the robots, the circuits – checked tick by
  tick (`native_check`, the live check).

**Live check** (*Check against original*): a second `Machine` runs the same
world with every native off, fed the same input before each tick, and after
each tick memory, bank 1 and the page are compared – `native_check`'s
lock‑step, live, on what the player does. The first difference shows the
tick, the addresses and the natives that ran in it. It costs one 6502 tick
per tick (about 200 K cycles).

**Enhanced natives** – routines that deliberately do something else (a
fix, a gameplay change) – would be marked as such, off by default; the live
check then shows where they take the game away from the original. The exact
ones stay exact.

## The native layer

Built 2026‑11‑05 (in place of the modern text of 2026‑11‑04, which drew the
page again without its letters on a copy). The canvas shows each page as
three layers (`PageLayers`), the Mac drawing at its resolution where a
routine draws on the native layer, the Apple's pixels everywhere else:

1. **The page**, as the game drew it, in memory: byte for byte the
   original's, 6502 code and natives alike. Not shown in the canvas; it is
   what the game, `native_check`, the thumbnails and the map see.
2. **The page without the native layer's drawings** (`Page.apple`): what
   everything else drew, as Apple pixels (`HiresImage`).
3. **The native layer** (`Page.items`, `LayerItem`): what the routines that
   draw on it drew, as what it is – a text, a sprite with its rows,
   position and colour, a plot or a line – drawn by the Mac over layer 2 (`NativeLayer`, a
   Canvas in the engine's coordinates scaled to the canvas), in the order
   drawn.

Each page (1 and 2) has its own layers 2 and 3: the game draws on the page
not on screen and flips ($C054/$C055), and the canvas shows the page on
screen with its layers (`Machine.shownFrame`).

* **Who draws on layer 3** (`LayerRoutine`): DRAW_TEXT ($A2EA,
  `DrawnText`), DRAW_BIG_TEXT ($A3E1, reached only by DRAW_TEXT's jump for
  style 2, followed there), DRAW_SPRITE ($AF1F, `LayerSprite`), PLOT ($A14D,
  its colour in A), HORIZONTAL_LINE ($A04C) and VERTICAL_LINE ($9FC4)
  (`LayerLine`): after the tiles, everything the draw phase draws (no world
  code writes the page there, 2026‑11‑05), so layer 3 has it in the game's
  order – the robots' faces are a black sprite with plots and lines over it
  (the wallhugger's animation), the flip‑flop robot's band a black line over
  its body. They draw on the page as
  ever – the game's memory stays the original's, natives and their
  switches interchangeable at any call – and nothing they write goes to
  layer 2. As 6502 code the machine follows them (`Machine.followDrawing`,
  traps that look and change nothing): at the entry the item from the
  parameters, then nothing to layer 2 until the routine returns (where the
  JSR on the stack goes back to, the stack pointer 2 higher; big text's
  letters are DRAW_SPRITE's inside DRAW_TEXT's, a short line's plots
  HORIZONTAL_LINE's, part of its item). The Swift versions, which the robot
  drawing natives call, do the same themselves (`RAM.drawingOnLayer`), with
  the 6502 code's calls (VERTICAL_LINE plots inline, HORIZONTAL_LINE calls
  PLOT), so natives and 6502 code make the same layers.
* **Layer 2** follows everything else written to a page: the 6502 code's
  writes (the CPU's `watchedPages`/`onWrite`, $2000‑$5FFF) and the natives'
  (`RAM`). Only the bits a write changed go there (the user's choice,
  2026‑11‑05, to see it): the 6502 code that draws after a text or sprite
  reads the page with their pixels in it and writes it back with its own;
  the bits it didn't change stay as layer 2 had them. Its blind spot: a bit
  the later drawing sets that the layer's drawing had set already (ORed in,
  or stored over it) stays out of layer 2; the palette bit the same way.
  With only the texts and sprites on layer 3 that was 6‑170 bytes a world,
  the wires and pins drawn over the robots' parts; with the plots and lines
  too, none: only the tiles draw outside layer 3, before it. A routine
  switched off draws into layer 2 and can bring the blind spot back.
* **When:** a page's layer 3 is emptied where its drawing starts
  (DRAW_ROOM_TILES draws all of it: the draw phase and the worlds' own
  screens – the help, the Esc and chip rooms, the way out of the sewer);
  layer 2 is taken from the page at its first drawing on layer 3 and
  followed from there; without any, layer 2 is the page. The machine keeps
  the layers while a world runs (`GameLoop.keepsLayers`), not in the loader
  (its code lies where the engine's routines were); its copies keep them, so
  the previews and *Smooth*'s in‑between frames come with theirs.
* **What it costs:** about 0.15 ms a tick (3.9 against 3.75 ms in a
  Release build), the writes to the pages followed and the drawings noted.
* **Texts** in a modern monospaced font, SF Mono Medium (`NativeLayer.font`;
  the other fonts of `TextFont` wait for a settings menu – the user,
  2026‑11‑05), of the Apple's letter size: each letter centred in its cell,
  its capitals as high as the Apple's (7 lines, big text 14) on the Apple's
  baseline, at most as wide as the cell; white (green on the monochrome
  screen), big text in the colour its patterns show. The font's own signs
  become what they show (`DrawnText.characters`): { } ~ DEL ← → ↑ ↓, ^ a
  bullet, \` and " the quotes “ ”, ' ’; hyphens next to an arrow are its
  shaft, a line through their cells (the Apple's hyphen fills its cell); an
  accent another text draws over a letter is merged into it (Level 2's $25
  "Musé": a / five lines above the e). The arrows and their shafts come from
  SF Mono (Menlo's are small, Monaco has no ← ↑), ← and → lowered onto the
  line of its ─, so an arrow and its shaft make one line.
* **Sprites, plots and lines** as the pixels they light, at the Apple's
  resolution, drawn crisp at the Mac's (`Pixels` in NativeLayer.swift): the
  pixels a drawing covers (a sprite bit two across, bit 6 on the left; a
  plot two; a line from its first to its last unit) lit where its colour's
  patterns light them (by byte column; PLOT's tables light the same pixels
  as LINE_PATTERNS), cleared (black) elsewhere and all of them where the
  patterns light none, as on the page. Consecutive drawings go into one
  buffer, in order (a text in between draws it first): an unlit pixel
  between two lit ones shows their colour (white and a colour: the colour),
  as the colour screen shows a colour's every other pixel – so two sprites
  side by side make one body, a spark is one pixel; green and the pixels
  lit on the monochrome screen. The Apple's drawing without its colour
  fringes. (First drawn two pixels a bit, which made the coloured shapes a
  pixel wider and the sparks dashes – the user, 2026‑11‑05: "the sprites
  are wrong".) Where new drawings of the sprites come in, keyed by the rows
  drawn rather than the sprite number (the worlds' code rewrites sprites as
  it runs: Level 1's room $0E, the big text).
* **The switches:** one per routine (the user, 2026‑11‑05, in place of one
  *NATIVE_LAYER* switch), under *Native layer* in the *Native routines* list
  (outside *All*, which is about the engine), kept in `nativesOff` with the
  natives' switches (`Machine.switchedOff`, `PageLayers.switchOff`): off, the
  routine's drawing stays the Apple's pixels, in layer 2. From the next page
  drawn. The thumbnails and the map show the page.
* Checked headless by `Data/layer_check.sh` (v1.1, every world): memory,
  bank 1 and the page the same keeping the layers and not; every room drawn
  with the layers (natives on, and all 6502 code) against the page the 6502
  code draws with every write inside the layer's routines undone – layer 2
  differs from it only in bytes they drew in (the blind spot, counted: 0);
  the loop's own page on screen with the same layers; every room's texts;
  the letters never two in one cell (but in the junk of room $3F); the help
  (`?`): layer 2 the page without the letters.

### More on layer 3

No SpriteKit or GameplayKit (the user, 2026‑11‑05): the native layer is
drawn by the Mac in the canvas, over the Apple's pixels. Next:

* **More routines drawing on it**, each where it is called: the tiles
  (SET_TILE_COLOURS) – and then the robots as robots, not as their sprites
  and lines, the wires as wires.
* **New drawings of the sprites**, by the rows drawn and the colour.
* **What is still drawn outside:** the worlds' own code that writes the page
  (found by the same kind of check: what layer 2 still has once every
  engine routine draws on layer 3).
* **Comparing:** *Split* (the page and the layers side by side) and
  *Overlay*, from the same tick.

## Sound

* **Speaker** (now): the clicks as the Apple's speaker makes them.
* **Modern:** the native PLAY_SOUNDS knows which sound plays (the 37 of
  `GameSounds`), so a synthesized or sampled version can play at the same
  moment. Output only: the game still waits the sound's cycles, as on the
  Apple, whichever is heard.

## Input

Input stays at the devices (keyboard, paddles, buttons) for both views:
the game is the same whichever front end is on, so comparing them is fair.
Modern input is mapping onto those devices (held keys, the controller –
done). Anything that goes around READ_INPUT (pointing where to walk, say)
changes the game and would be an enhanced native.

**The mouse** is the game's own: an Apple mouse card (`AppleMouse`, slot 4)
for the mouse mode Robot Odyssey has (INPUT_DEVICE 2, Engine.md "Input"),
so everything but taking the Mac's mouse is the game's code (the user,
2026‑11‑04, after trying drags: moving objects was cheating everywhere,
the drag kept the button from being the game's, an open toolbox's labels
and tools stayed behind).

* **Taking it:** in *Play*, a press of ⌘ alone (down and up, nothing in
  between) while the canvas has the keyboard – the only way in and out
  (the user, 2026‑11‑04: no click on the player, no hand pointer). The
  pointer hides and is held where it is (`MouseCapture`:
  `NSCursor.hide`, `CGAssociateMouseAndMouseCursorPosition`); the mouse's
  motion and its left button go to the card, no view sees them. ⌘ alone
  again gives it back, and so do leaving *Play*, another window or app
  coming up, the loader taking over (its prompts may want the pointer), a
  restart; the pointer comes back on the player
  (`CGWarpMouseCursorPosition`).
* **The card** goes in where the next tick starts (`GameLoop.mouse`,
  `Machine.plugMouse`): its ROM page at $C400 (the Pascal bytes, the
  mouse's ID $C40C = $20 and $C4FB = $D6, the firmware's offsets), the game
  told as DETECT_JOYSTICK tells it when it finds one (INPUT_DEVICE 2,
  SLOT_POINTER $C400), and the game's own set‑up run (SET_UP_MOUSE $AC76:
  MOUSE_SLOT, SETMOUSE, CLEARMOUSE, CLAMPMOUSE, HOME_MOUSE; registers and
  cycles put back). It comes out where a tick starts once the mouse is
  given back (not halfway through READ_INPUT's calls), and as the world
  hands back to the loader (before a save): INPUT_DEVICE, SLOT_POINTER and
  the ROM page as they were. While the mouse stays taken it goes in again
  in the next world's first tick. INPUT_DEVICE is set only while the card
  is in, so a game controller still works the rest of the time
  (DETECT_JOYSTICK prefers the joystick, which the mouse mode doesn't read).
* **Walking:** every tick READ_DEVICE reads the card (READMOUSE): its
  position, the motion since the last tick, halved, is the move
  (READ_MOUSE), at most 7 across and 15 up or down (LIMIT_MOVE), stopped
  at walls (not with WALLS_ON 0), kept on the screen, through exits; then
  the mouse goes back to (0, 0) (POSMOUSE). Motion past the limit is lost:
  the player is never faster than by the keys, the original's pace, with
  its walking frames, its carrying (CARRY_WIRES by KEEP_MOVE) and the
  sentries as ever. The motion is the canvas's: a unit across is 4 image
  pixels, up or down 2, in points at the canvas's size, 2 counts a unit
  (what is less than a unit waits for more, `ViewerModel.moveMouse`). The
  keys walk too: in the mouse mode a movement key typed comes first.
* **The button** is BUTTON_A (READ_MOUSE) for one tick per press, held or
  not, as the space key's: take, drop, take out of the toolbox, the remote,
  the soldering pen (a click on a pin, walk, a click on the other). The card
  reports a press at the first read after the button went down only and
  never sets status bit 6 (down at the last read), which READ_MOUSE takes
  as down too (2026‑11‑04, the user: presses came double). The game reads a
  button down over two ticks as one press held, and a press held on a pin
  with a wire cuts the wire and then starts a new one there: SOLDER_TOUCH's
  UNSOLDER leaves GRAB_STATE at 1 and SOLDER_WIRE takes it as a new press in
  the next tick (with the card's real status every click would). A held
  joystick button would do the same (the controller's buttons stay down
  while held). The drag from pin to pin that pressed again on release is
  gone too: a click's wobble of a unit made it a second press.
* **Selecting** takes Option or Control: an Option‑ or Control‑click
  selects what is there.

The firmware is the AppleMouse II's calls as the game makes them (CALL_MOUSE
jumps to $C400 + the offset in the table at $C412 + Y; native hooks return
like RTS, carry clear, no time taken), answered through slot 4's screen
holes (text page 1, empty in every world). CLAMPMOUSE's bounds come from
slot 0's holes; the game's have high bytes 0 ($00E4–$001C across,
$00C4–$003C up and down), read as signed bytes (−28…28, −60…60). The halving
(HALVE_MOUSE_MOVE) skips only a IIc ($FBC0 = 0); in every world that byte
is language‑card RAM and not 0. Checked headless by `Data/mouse_check.sh`
(v1.0 and v1.1).

The drags this replaces (2026‑11‑03: the player and the objects it could
take moved to the pointer at once, wires and all; the pen's tip at the
pointer) are on the branch `snapshot/mouse-drag`.

## Order

1. Switches per native, taking effect at the next instruction – done.
   The texts in a modern font – done; since 2026‑11‑05 the native layer
   (texts, sprites, plots and lines, "The native layer").
2. The live check against a machine without natives.
3. More routines on the native layer (the tiles, the robots, the wires);
   find what draws outside them.
4. New drawings of the sprites; *Split* and *Overlay*.
5. Modern sound by sound number.
6. Natives for the carrying and the wires: MOVE_LINKED_OBJECTS/FOLLOW_LINK
   ($9C53/$9C88, engine main), then CARRY_WIRES in each engine (levels
   $B8E6, kit $F367, lab $F0A0, ~1.3 KB each with the gates' and chips'
   pins and UNSOLDER) and the soldering (TIP_ON_PIN, SOLDER_WIRE,
   SOLDER_TOUCH), each against the original by `native_check` (random held
   objects, wires and moves).
7. ~~The natives' cycle counts~~ – dropped (2026‑11‑03): natives make the
   game faster on purpose; only what a tick does must stay the original's.
