# Switches: original against native, Apple against modern – plan

Thoughts (2026‑11‑03); step 1, the switches, is built (below). The idea: switches in
the inspector that turn each native routine on or off, and a modern front
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
switch in the inspector's *Native routines* list (its entry point beside
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

**The mouse** (built 2026‑11‑03, `MouseHand`, applied where each tick
starts): a drag on the canvas takes hold of what is under the pointer
(a pixel of its sprite) in the running game.

* **The player** (*Play* only), or anything it carries: the mouse steers
  the joystick. Each tick the paddles go to the position whose move in the
  game's joystick table comes nearest the target without passing it, so
  READ_INPUT walks the player there as a joystick would: 7 across and 15 up
  or down a tick, stopped by walls (sliding along them), with the walking
  sprite, what it holds and the robots' parts following as ever. This part
  is device input only, nothing a real joystick couldn't do. Through an
  exit the target goes along into the next room (its coordinates wrapped as
  MOVE_OBJECT_XY wraps the player's), so dragging on past the canvas's edge
  walks on into the next room; let go, the player walks on to the target
  and stops there (or where it can't go on). A movement key takes over.
* **An object** (by the root of its OBJ_LINK chain, as GRAB_AND_CARRY takes
  it: a robot's body, a gate's base) goes to the target at once each tick,
  in the steps the game's own mouse mode moves the player by (READ_DEVICE
  at $A9FB: LIMIT_MOVE to 7 and 15, STOP_AT_WALLS, KEEP_ON_SCREEN,
  MOVE_OBJECT, the native ports), so it stays an object of its room that
  the player can take with the button. A wall in the way drops it there, an
  exit drops it on the other side, the player taking it ends the drag. One
  lying on a wall moves freely until it is off it. Everything else those
  routines write (the move, CUR_OBJECT, the wall tests' temporaries) and
  the registers are put back, so the tick runs as it would have but for
  where objects are. This part is an enhancement: no Apple input does it.
* **A click** selects as before; in *Play*, on the player or what it
  carries, it is also the game's button (button 1 for a tick, as the game's
  mouse mode takes the mouse button for BUTTON_A): take or drop, the remote
  control, and the soldering pen – drag the pen to a pin, click it. A click
  while the player still walks to a drag's target waits until it is there.

Not done: the cursor stays where it is when the player walks into the next
room (the view switches under it). Warping the cursor to the opposite edge
(`CGWarpMouseCursorPosition`, by the room's width in view points) would keep
it on the player; a modifier‑click on a pin could walk the pen there and
press.

## Order

1. Switches per native, taking effect at the next instruction – done.
2. The live check against a machine without natives.
3. The display list from the draw phase, with the rasterise‑and‑compare
   check; find what draws outside the primitives.
4. The SpriteKit view from the display list; *Split* and *Overlay*.
5. Modern sound by sound number.
6. ~~The natives' cycle counts~~ – dropped (2026‑11‑03): natives make the
   game faster on purpose; only what a tick does must stay the original's.
