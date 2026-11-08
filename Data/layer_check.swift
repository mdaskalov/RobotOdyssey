// Checks the canvas's layers of the pages (PageLayers, Machine.layers:
// layer 1 the page, layer 2 the page without what the routines that draw on
// layer 3 draw -- the natives with Native.Flags.drawsOnLayer3: the texts,
// sprites, plots and lines --,
// layer 3 those drawings as items), headless, in every world:
//
//   memory:  a loop keeping the layers and one without, from the world's
//            start, the same keys typed (walking, then ? for the help) --
//            memory, bank 1 and the page on screen the same after every
//            tick: they only look; and what keeping them costs;
//   rooms:   every room drawn by the draw phase from where the loop draws it,
//            with the layers (natives on, and all 6502 code), against the
//            page the 6502 code draws with every write inside those routines
//            undone (the page without them): layer 2 differs from it only in
//            bytes they drew in (the bits drawing after them set again that
//            they had set already: counted, not a failure -- none while
//            everything after the tiles draws on layer 3); the canvas's
//            Apple pixels (LayerPixels: layer 2 with layer 3's sprites,
//            plots and lines drawn on it and the writes between them, in
//            order) the page but for the letters' cells, with every routine
//            on and with DRAW_SPRITE, PLOT, HORIZONTAL_LINE, VERTICAL_LINE,
//            the plots and lines, or all switched off (drawn in their place:
//            the same pixels on and off);
//            the loop's own
//            page on screen (shownFrame) has the same layers; the texts as many as the room's table has (as the
//            draw finds it: the worlds' code moves texts; it may draw more);
//            the letters as the canvas draws them (DrawnText.characters):
//            no two in one cell -- an accent another text draws over a
//            letter merged into it (Level 2's "Musé") -- except in room $3F
//            (nowhere: its texts are junk);
//   robots:  with each of those switch sets, the world run from its start
//            (robotTicks ticks, no keys) and every room a robot is in
//            previewed each tick: the canvas's Apple pixels the page but for
//            the letters' cells -- the robots move, their bumpers light, so
//            the drawings meet in ways a room's first draw doesn't (a sprite
//            given the third byte's palette bit where a switched-off
//            VERTICAL_LINE writes later: LayerPixels draws on layer 2 as it
//            was at the first drawing, PageFrame.start);
//   help:    ? typed (in the levels SHOW_TEXT_ROOM: the help room, drawn
//            outside the draw phase, then a wait for a key) -- the help's
//            page comes with its texts, layer 2 differing from the page only
//            in the letters' cells, and with the letters ORed back in the page.
//
// Build and run with layer_check.sh (compiles this file with the app's sources).
import Foundation
import MOS6502

@main
struct LayerCheck {
    static var failures = 0

    static func fail(_ s: String) {
        failures += 1
        print("  FAIL " + s)
    }

    static func check(_ ok: Bool, _ s: String) {
        if ok { print("  ok   " + s) } else { fail(s) }
    }

    static func hex(_ v: Int) -> String { String(format: "$%02X", v) }

    static func main() throws {
        let paths = CommandLine.arguments.dropFirst()
        guard !paths.isEmpty else {
            print("usage: layer_check SIDE_A.dsk SIDE_B.dsk")
            exit(2)
        }
        var set = DiskSet(version: nil)
        for p in paths {
            let d = try DiskImage(name: (p as NSString).lastPathComponent, data: Data(contentsOf: URL(fileURLWithPath: p)))
            if case .programSide(let side, let version) = d.role {
                set.version = version
                if side == .a { set.sideA = d } else { set.sideB = d }
            }
        }
        let (worlds, errors) = WorldBuilder(disks: set).buildAll()
        errors.forEach { print("build error: \($0)") }
        for world in worlds {
            print("\(world.name):")
            let game = try GameScreen(world: world)
            try memory(game)
            try rooms(world, game)
            try robots(world, game)
            try help(game)
        }
        print(failures == 0 ? "all ok" : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: pages

    static func texts(_ items: [LayerItem]) -> [DrawnText] {
        items.compactMap { if case .text(let t) = $0 { t } else { nil } }
    }

    static func sprites(_ items: [LayerItem]) -> Int {
        items.count { if case .sprite = $0 { true } else { false } }
    }

    static func lines(_ items: [LayerItem]) -> Int {
        items.count { if case .line = $0 { true } else { false } }
    }

    /// The layers without the writes between the drawings (`PageWrites`):
    /// natives and 6502 code may write a byte in other steps.
    static func drawings(_ items: [LayerItem]) -> [LayerItem] {
        items.filter { if case .writes = $0 { false } else { true } }
    }

    /// The bytes the writes between the drawings changed.
    static func written(_ items: [LayerItem]) -> Int {
        items.reduce(0) { n, item in
            guard case .writes(let w) = item else { return n }
            var count = 0
            w.forEach { _, _, _ in count += 1 }
            return n + count
        }
    }

    /// The canvas's Apple pixels (`LayerPixels`) against the page: the bytes
    /// that differ outside the texts' cells.
    static func pixelsDiffer(_ frame: PageFrame) -> Int {
        let cells = Set(texts(frame.items).flatMap { t in t.letters.flatMap { cell(t, $0) } })
        let pixels = LayerPixels(frame).screen.bytes, page = frame.page.bytes
        return (0 ..< page.count).count { pixels[$0] != page[$0] && !cells.contains($0) }
    }

    /// Natives that draw on layer 3 switched off for the pixels check.
    static let switchSets: [(name: String, off: Set<String>)] = [
        ("all on", []),
        ("DRAW_SPRITE off", names([\.drawSprite])),
        ("PLOT off", names([\.plot])),
        ("HORIZONTAL_LINE off", names([\.horizontalLine])),
        ("VERTICAL_LINE off", names([\.verticalLine])),
        ("plots and lines off", names([\.plot, \.horizontalLine, \.verticalLine])),
        ("sprites, plots and lines off", names([\.drawSprite, \.plot, \.horizontalLine, \.verticalLine])),
    ]

    static func names(_ routines: [RoutineSymbol]) -> Set<String> { Set(routines.map(GameSymbols.name(of:))) }

    /// The bytes of the page a letter's cell takes (top line first, 40 a line):
    /// a normal letter its byte column on 8 lines, a big one the bytes its
    /// sprite covers (and the third byte DRAW_SPRITE may give the palette bit) on 16.
    static func cell(_ text: DrawnText, _ letter: DrawnText.Letter) -> [Int] {
        let lines = text.big ? 16 : 8
        let columns = text.big ? Array(letter.x / 7 ... min((letter.x + 13) / 7 + 1, 39)) : [letter.x / 7]
        return (0 ..< lines).flatMap { r in
            let line = 191 - (letter.y + r)
            return line < 0 ? [] : columns.map { line * 40 + $0 }
        }
    }

    /// The bytes of the page a sprite's rows draw in (top line first): from
    /// its x's byte column the two it covers and the third DRAW_SPRITE may
    /// give the palette bit, on the lines of its rows that have bits.
    static func cells(_ sprite: LayerSprite) -> [Int] {
        let first = 2 * sprite.x / 7
        return sprite.rows.enumerated().flatMap { r, bits -> [Int] in
            let line = 191 - (sprite.y + r)
            return bits == 0 || line < 0 ? [] : (first ... min(first + 2, 39)).map { line * 40 + $0 }
        }
    }

    /// The bytes layer 3's drawings drew in.
    static func drawnIn(_ items: [LayerItem]) -> Set<Int> {
        Set(items.flatMap { item -> [Int] in
            switch item {
            case .text(let t): t.letters.flatMap { cell(t, $0) }
            case .sprite(let s): cells(s)
            case .line(let l):
                (l.y ..< l.y + l.height).flatMap { y -> [Int] in
                    let line = 191 - y
                    return line < 0 ? [] : (l.x / 7 ... min((l.x + l.width) / 7, 39)).map { line * 40 + $0 }
                }
            case .writes: []        // in layer 2 too
            }
        })
    }

    /// The page as the 6502 code draws it without the routines that draw on
    /// layer 3: every write to the page inside them undone (their drawing
    /// otherwise runs, its temporaries and all).
    static func withoutLayerRoutines(_ world: World, _ game: GameScreen, room: Int,
                                     _ start: (memory: [UInt8], bank1: [UInt8])) throws -> [UInt8] {
        let m = machine(world, start)
        m.nativesEnabled = false
        let layers = PageLayers()
        m.layers = layers
        let follow = m.cpu.onWrite
        m.cpu.onWrite = { [unowned m] a, old, new in
            if layers.drawing > 0 { m.cpu.mem[Int(a)] = old } else { follow(a, old, new) }
        }
        _ = try game.phase.draw(room: room, on: m)
        return m.drawnScreen().bytes
    }

    /// A page of texts only: layer 2 against the page, differences only in
    /// the letters' cells; and the letters put back (normal ones ORed from
    /// the font, big ones' cells copied): the bytes that still differ.
    static func compare(_ frame: PageFrame, _ mem: [UInt8]) -> (outside: Int, differing: Int) {
        var cells = Set<Int>()
        var rebuilt = frame.apple.bytes
        for text in texts(frame.items) {
            for letter in text.letters {
                let c = cell(text, letter)
                cells.formUnion(c)
                if text.big {
                    for i in c { rebuilt[i] = frame.page.bytes[i] }
                } else {
                    for (r, i) in c.enumerated() {
                        rebuilt[i] |= mem[GameSymbols.address(\.fontBase) + r * 0x60 + Int(letter.code)]
                    }
                }
            }
        }
        let page = frame.page.bytes, apple = frame.apple.bytes
        let outside = (0 ..< page.count).count { !cells.contains($0) && apple[$0] != page[$0] }
        let differing = (0 ..< page.count).count { rebuilt[$0] != page[$0] }
        return (outside, differing)
    }

    /// A machine at `start` (memory, bank 1) with the world's natives, as the loop's.
    static func machine(_ world: World, _ start: (memory: [UInt8], bank1: [UInt8])) -> Machine {
        let m = Machine(memory: start.memory, bank1: start.bank1, variant: world.codeCheck?.variant)
        m.install(world.codeCheck?.natives ?? [])
        return m
    }

    // MARK: the checks

    /// Movement keys, then ? (the help) and Return (back).
    static let keys: [UInt8?] = [0xCB, 0xCB, 0xCB, nil, 0xCA, 0xCA, 0xCD, 0xC9, nil, 0xBF, nil, 0x8D, nil, nil]

    static func memory(_ game: GameScreen) throws {
        let on = game.loop(room: nil), off = game.loop(room: nil)
        off.keepsLayers = false
        var same = true, ticks = 0, items = 0
        var time = (on: 0.0, off: 0.0)
        for key in keys {
            for loop in [on, off] {
                if let key { loop.devices.type(key) }
                let t0 = Date()
                // A tick, or 2 M cycles where it waits for a key.
                do { try loop.runTick(maxSteps: 1_000_000) } catch CPU6502.CPUError.tooManySteps {}
                if loop === on { time.on += Date().timeIntervalSince(t0) } else { time.off += Date().timeIntervalSince(t0) }
            }
            ticks += 1
            items += on.shownFrame().items.count
            if on.memory != off.memory || on.bank1 != off.bank1 || on.screen().bytes != off.screen().bytes {
                same = false
                break
            }
        }
        check(same, "memory: \(ticks) ticks keeping the layers and not, the same memory, bank 1 and page (\(items) items shown)"
              + String(format: "; %.2f ms against %.2f ms a tick", time.on / Double(ticks) * 1000, time.off / Double(ticks) * 1000))
    }

    static func rooms(_ world: World, _ game: GameScreen) throws {
        var rooms = 0, layered = 0, textRooms = 0, spriteCount = 0, lineCount = 0, textCount = 0
        var outside: [String] = [], blind: [String] = [], blindBytes = 0, live: [String] = []
        var missing: [String] = [], accented: [String] = [], overlapping: [String] = []
        var pixels: [String] = [], writes = [Int](repeating: 0, count: switchSets.count)
        for room in 0 ..< World.roomCount where world.codeRooms[room] == nil {
            let loop = game.loop(room: room)
            for _ in 0 ..< 2 { try loop.runTick() }
            guard loop.shownRoom == room else { continue }
            rooms += 1
            let start = loop.memory(drawing: room)
            let without = try withoutLayerRoutines(world, game, room: room, start)
            var frames: [PageFrame] = []
            for natives in [true, false] {
                let m = machine(world, start)
                m.nativesEnabled = natives
                m.layers = PageLayers()
                _ = try game.phase.draw(room: room, on: m)
                frames.append(m.drawnFrame())
            }
            let frame = frames[0]
            guard !frame.items.isEmpty else { continue }
            layered += 1
            spriteCount += sprites(frame.items)
            lineCount += lines(frame.items)
            for (f, name) in zip(frames, ["natives", "6502"]) {
                let apple = f.apple.bytes, drawnIn = drawnIn(f.items)
                let out = (0 ..< apple.count).count { apple[$0] != without[$0] && !drawnIn.contains($0) }
                if out != 0 { outside.append("\(hex(room)) \(name) (\(out) bytes)") }
                let inside = (0 ..< apple.count).count { apple[$0] != without[$0] }
                if inside != 0, name == "natives" {
                    blind.append("\(hex(room)) (\(inside))")
                    blindBytes += inside
                }
            }
            if frames[1].apple.bytes != frame.apple.bytes || drawings(frames[1].items) != drawings(frame.items)
                || LayerPixels(frames[1]).screen.bytes != LayerPixels(frame).screen.bytes {
                live.append("\(hex(room)) (6502 code)")
            }
            // The canvas's Apple pixels: the page but for the letters, any routine switched off.
            for (k, switches) in switchSets.enumerated() {
                let m = machine(world, start)
                m.layers = PageLayers()
                m.switchedOff = switches.off
                _ = try game.phase.draw(room: room, on: m)
                let drawn = m.drawnFrame()
                writes[k] += written(drawn.items)
                let differ = pixelsDiffer(drawn)
                if differ != 0 { pixels.append("\(hex(room)) \(switches.name) (\(differ) bytes)") }
            }
            let shown = loop.shownFrame()
            if shown.page.bytes != frame.page.bytes || shown.apple.bytes != frame.apple.bytes || shown.items != frame.items {
                live.append("\(hex(room)) (on screen)")
            }
            // The texts.
            let drawn = texts(frame.items)
            guard !drawn.isEmpty || !world.textsInRoom(room).isEmpty else { continue }
            textRooms += 1
            textCount += drawn.count
            let state = world.with(mem: start.memory, bank1: start.bank1)
            let table = state.textsInRoom(room).map(state.text).filter { t in t.bytes.contains { $0 > 0xA0 } }
            if drawn.count < table.count { missing.append("\(hex(room)) (\(drawn.count) of \(table.count))") }
            // The letters the canvas draws, normal text: any two in one cell?
            var letters: [(letter: DrawnText.Letter, s: String)] = []
            for (text, cs) in zip(drawn, DrawnText.characters(drawn)) where !text.big {
                for (l, s) in zip(text.letters, cs) {
                    guard let s else { continue }
                    if !s.allSatisfy(\.isASCII), s.unicodeScalars.allSatisfy(\.properties.isAlphabetic) { accented.append("\(hex(room)) \(s)") }
                    letters.append((l, s))
                }
            }
            let pairs = letters.indices.flatMap { i in letters.indices.filter { $0 > i }.map { (i, $0) } }
            let shared = pairs.count { letters[$0.0].letter.x == letters[$0.1].letter.x && abs(letters[$0.0].letter.y - letters[$0.1].letter.y) < 8 }
            if shared > 0, room != 0x3F { overlapping.append("\(hex(room)) (\(shared))") }
        }
        print("  --   rooms: \(rooms) drawn, \(layered) with layer 3 (\(spriteCount) sprites, \(lineCount) plots and lines, \(textCount) texts in \(textRooms) rooms)")
        check(outside.isEmpty, "rooms: layer 2 the page without the layer routines' writes, but in the bytes they drew in"
              + (outside.isEmpty ? "" : " – not in " + outside.joined(separator: ", ")))
        print("  --   rooms: \(blindBytes) bytes differing in those: bits drawing after them set again"
              + (blind.isEmpty ? "" : ": " + blind.joined(separator: ", ")))
        check(pixels.isEmpty, "rooms: the canvas's Apple pixels (layers 2 and 3) the page but for the letters, "
              + zip(switchSets, writes).map { "\($0.name) (\($1) bytes written between the drawings)" }.joined(separator: ", ")
              + (pixels.isEmpty ? "" : " – not in " + pixels.prefix(12).joined(separator: ", ")))
        check(live.isEmpty, "rooms: the same layers with every routine as 6502 code, and on screen"
              + (live.isEmpty ? "" : " – not in " + live.joined(separator: ", ")))
        check(missing.isEmpty, "rooms: each with its texts" + (missing.isEmpty ? "" : " – missing in " + missing.joined(separator: ", ")))
        check(overlapping.isEmpty, "rooms: the letters as the canvas draws them, never two in one cell"
              + (accented.isEmpty ? "" : " (accented: " + accented.joined(separator: ", ") + ")")
              + (overlapping.isEmpty ? "" : " – two in one in " + overlapping.joined(separator: ", ")))
    }

    /// Ticks the robots check runs each switch set (Level 1's lost palette
    /// bit came at tick 2 with VERTICAL_LINE off, at tick 185 with
    /// HORIZONTAL_LINE off).
    static let robotTicks = 300

    static func robots(_ world: World, _ game: GameScreen) throws {
        var frames = 0, failed: [String] = []
        for switches in switchSets {
            let loop = game.loop(room: nil)
            loop.switchedOff = switches.off
            var bad = 0
            for _ in 0 ..< robotTicks {
                do { try loop.runTick(maxSteps: 2_000_000) } catch CPU6502.CPUError.tooManySteps {}
                let now = world.with(mem: loop.memory, bank1: loop.bank1)
                let rooms = Set(now.robots.map { now.object($0.object).room })
                for room in rooms where room < World.roomCount && world.codeRooms[room] == nil {
                    guard let frame = try? loop.previewFrame(room: room), !frame.items.isEmpty else { continue }
                    frames += 1
                    if pixelsDiffer(frame) != 0 { bad += 1 }
                }
            }
            if bad != 0 { failed.append("\(switches.name) (\(bad) frames)") }
        }
        check(failed.isEmpty, "robots: \(robotTicks) ticks from the start with each switch set, \(frames) frames of the rooms "
              + "robots are in, the canvas's Apple pixels the page but for the letters"
              + (failed.isEmpty ? "" : " – not with " + failed.joined(separator: ", ")))
    }

    static func help(_ game: GameScreen) throws {
        let loop = game.loop(room: nil)
        try loop.runTick()
        let flips = loop.flips
        loop.devices.type(0xBF)                     // ?
        try loop.run(until: loop.cycles + 2_000_000)
        let frame = loop.shownFrame()
        guard loop.flips > flips, !texts(frame.items).isEmpty else {
            print("  --   help: ? shows no text page waiting for a key here")
            return
        }
        let c = compare(frame, loop.memory)
        check(c.outside == 0 && c.differing == 0 && sprites(frame.items) == 0,
              "help: ? – a page of \(texts(frame.items).count) texts (\(loop.flips - flips) flips), layer 2 differs from the page "
              + "only in their cells, with the letters put back it is the page (\(c.outside) bytes outside, \(c.differing) differ)")
    }
}
