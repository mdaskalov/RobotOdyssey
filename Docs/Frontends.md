# Switches: original against native, Apple against modern – plan

Thoughts (2026‑11‑03); step 1, the switches, is built (below). The idea: switches in
the *Current Room* panel that turn each native routine on or off, and a modern front
end (SpriteKit drawing, modern sound) beside the Apple's, so every
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

## A modern view (SpriteKit)

### Not by drawing natives into SpriteKit

DRAW_SPRITE drawing into SpriteKit in place of the page would break the
contract: the page is memory, so `native_check` would fail, turning it off
mid‑game would leave a page half drawn, *Smooth* (which redraws from a
page's draw start) and the room thumbnails (the room's own draw phase)
would lose their picture, and the worlds' own code that writes to the page
would be lost.

### From the draw phase, as a display list

Instead, record what the draw phase draws and render that. The draw phase
runs as now (6502 or natives, either), the page is made as now, and the
record is a side product:

* **Primitives** where the engine draws: DRAW_SPRITE(_COLOUR) ($AF1F, with
  its rows, x/y and patterns – `DrawnSprite` records that already for
  *Other sprites drawn*), PLOT ($A14D), HORIZONTAL_LINE/VERTICAL_LINE,
  DRAW_BOX, FILL_TILE (walls), the letters (DRAW_TEXT, DRAW_BIG_TEXT), each
  with the main‑loop routine that drew it (DRAW_ROOM_OBJECTS, DRAW_ROBOTS,
  DRAW_WIRES, the world's code by address).
* **Observers, not replacements:** hooks at these entries that note the
  call and let the routine (6502 or native) run, so the record comes from
  the pass that draws the page, not an extra one. The natives that draw
  (RobotDrawing) report their primitives the same way.
* **Complete, checked:** rasterising the list into a page must give the
  page byte for byte, every tick, every world – the same kind of check as
  `native_check`. Where it doesn't, something writes to $2000‑$5FFF outside
  the primitives (a world's own drawing code; to be found): that part shows
  as the Apple page, as a texture layer, until it has a primitive of its
  own.

### SpriteKit

* **Textures, made at world load:** the 64 sprites ($6A00, 16 rows, row 0
  at the bottom) in each colour (COLOUR_PATTERN0/1). The worlds' code
  rewrites sprites as it runs (Level 1's room $0E, the big text), so a
  texture is keyed by the rows and patterns drawn, not the sprite number:
  a cache filled at world load, added to when new rows turn up.
* **Coordinates:** object coordinates count y from the bottom, as SpriteKit
  does; walls are the room's 20×12 tiles, wires the L‑shaped lines.
* **Nodes that last:** a node per object (by its number from
  DRAW_ROOM_OBJECTS), per robot part and per wire, kept from tick to tick,
  so movement can be animated over the tick at display rate (SKAction) in
  place of *Smooth*'s in‑between draw phases.
* **What it can improve:** any scale and filtering, real colours per colour
  index in place of artifact colours, hot wires (colour 5) glowing, scrolling
  into the next room instead of a cut, later redrawn sprites at a higher
  resolution.

### Comparing

*Display*: **Apple** (the page), **Modern** (SpriteKit), **Split** (both,
side by side), **Overlay** (the modern view over the page, or the
difference of the two at the Apple's resolution). Both come from the same
tick, so they always show the same moment.

The map and thumbnails stay the room's own draw phase (as now); with the
modern view on, they can be made from the rooms' display lists the same
way.

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
2. The live check against a machine without natives.
3. The display list from the draw phase, with the rasterise‑and‑compare
   check; find what draws outside the primitives.
4. The SpriteKit view from the display list; *Split* and *Overlay*.
5. Modern sound by sound number.
6. Natives for the carrying and the wires: MOVE_LINKED_OBJECTS/FOLLOW_LINK
   ($9C53/$9C88, engine main), then CARRY_WIRES in each engine (levels
   $B8E6, kit $F367, lab $F0A0, ~1.3 KB each with the gates' and chips'
   pins and UNSOLDER) and the soldering (TIP_ON_PIN, SOLDER_WIRE,
   SOLDER_TOUCH), each against the original by `native_check` (random held
   objects, wires and moves).
7. ~~The natives' cycle counts~~ – dropped (2026‑11‑03): natives make the
   game faster on purpose; only what a tick does must stay the original's.
