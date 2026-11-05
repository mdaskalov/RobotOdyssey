import AppKit
import SwiftUI

/// The fonts the native layer's texts can take: monospaced ones, as the
/// game's letters are, which macOS has (`NativeLayer.font`: SF Mono Medium,
/// till a settings menu chooses).
enum TextFont: String, CaseIterable, Identifiable {
    case sfMono = "SF Mono", sfMonoMedium = "SF Mono Medium", menlo = "Menlo", monaco = "Monaco"
    case ptMono = "PT Mono", andaleMono = "Andale Mono", courierNew = "Courier New"

    var id: String { rawValue }

    func font(size: CGFloat) -> NSFont {
        switch self {
        case .sfMono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .sfMonoMedium: return .monospacedSystemFont(ofSize: size, weight: .medium)
        default:
            let name = [TextFont.menlo: "Menlo-Regular", .monaco: "Monaco", .ptMono: "PTMono-Regular",
                        .andaleMono: "AndaleMono", .courierNew: "CourierNewPSMT"][self]
            return name.flatMap { NSFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// The size whose capitals are `cap` high and whose letters (the zero's
    /// advance) are at most `width` wide, in points.
    func size(cap: CGFloat, width: CGFloat) -> CGFloat {
        let m = metrics
        return min(cap / m.cap, width / m.advance)
    }

    /// The font the arrows (← → ↑ ↓ and the shafts) come from with this one:
    /// SF Mono's, the clearest at this size, in every font (Menlo's are
    /// small, Monaco has no ← ↑).
    var arrows: TextFont { self == .sfMono ? .sfMono : .sfMonoMedium }

    /// How much lower than the font puts them its ← and → are drawn, per
    /// point: onto the line its ─ (an arrow's shaft) lies on, so an arrow
    /// and its shaft make one line (SF Mono's → is 0.75 lines above it).
    var arrowDrop: CGFloat { metrics.drop }

    /// Cap height, advance and arrow drop per point.
    private var metrics: (cap: CGFloat, advance: CGFloat, drop: CGFloat) {
        if let m = TextFont.metrics[self] { return m }
        let f = font(size: 100)
        let advance = NSAttributedString(string: "0", attributes: [.font: f]).size().width
        // A glyph's ink's middle, in the font's own glyph (0 where it has none).
        func middle(_ c: Character) -> CGFloat {
            var chars = Array(String(c).utf16), glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(f as CTFont, &chars, &glyphs, chars.count) else { return 0 }
            return CTFontGetBoundingRectsForGlyphs(f as CTFont, .default, &glyphs, nil, 1).midY
        }
        let m = (cap: f.capHeight / 100, advance: advance / 100, drop: (middle("→") - middle("─")) / 100)
        TextFont.metrics[self] = m
        return m
    }

    private static var metrics: [TextFont: (cap: CGFloat, advance: CGFloat, drop: CGFloat)] = [:]
}

/// Layer 3 of a page (`PageLayers`): what the routines that draw on it drew
/// (`LayerItem`), drawn by the Mac at its resolution over layer 2, in the
/// order drawn, in the engine's coordinates scaled to the canvas.
///
/// * **Texts** (DRAW_TEXT, DRAW_BIG_TEXT) in a modern font (`font`): each
///   letter in its cell (7 screen pixels, big text 14), its capitals as high
///   as the Apple's (7 lines, big text 14) on the Apple's baseline (above the
///   descenders' line, two for big text).  Normal text is white, big text in
///   its colour; green on the monochrome screen.  The letters are drawn as
///   `DrawnText.characters` makes them: the Apple's signs as what they are,
///   an arrow's shaft a line through the cells (the font's ─ widened), an
///   accent another text draws over a letter in the accented letter.  The
///   arrows and shafts come from SF Mono (`TextFont.arrows`), ← and →
///   lowered onto their shafts' line.
/// * **Sprites, plots and lines** (DRAW_SPRITE, PLOT, HORIZONTAL_LINE,
///   VERTICAL_LINE) as the pixels they light (`Pixels`): the Apple's drawing
///   without its colour fringes.  Where new drawings of the sprites come in.
struct NativeLayer: View, Equatable {
    /// The texts' font.
    static let font = TextFont.sfMonoMedium

    let items: [LayerItem]
    let mono: Bool

    var body: some View {
        Canvas { context, size in
            let scale = CGSize(width: size.width / CGFloat(HiresScreen.width), height: size.height / CGFloat(HiresScreen.height))
            let texts = items.compactMap { item -> DrawnText? in if case .text(let t) = item { t } else { nil } }
            let characters = DrawnText.characters(texts)
            var t = 0
            // The pixels drawn since the last text, drawn before the next.
            var pixels = Pixels(mono: mono)
            for item in items {
                switch item {
                case .text(let text):
                    pixels.draw(in: context, scale: scale)
                    draw(text, characters[t], in: context, scale: scale)
                    t += 1
                case .sprite(let sprite):
                    pixels.add(spans(sprite), even: sprite.patternEven, odd: sprite.patternOdd)
                case .line(let line):
                    let spans = (line.y ..< line.y + line.height).map { (line: $0, from: line.x, to: line.x + line.width) }
                    pixels.add(spans, even: line.patternEven, odd: line.patternOdd)
                }
            }
            pixels.draw(in: context, scale: scale)
        }
        .allowsHitTesting(false)
    }

    private func colour(_ rgb: HiresImage.RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    private static let arrowSigns: Set<String> = ["←", "→", "↑", "↓", DrawnText.shaft]

    private func draw(_ text: DrawnText, _ characters: [String?], in context: GraphicsContext, scale: CGSize) {
        let font = NativeLayer.font
        let cell = CGFloat(text.cellWidth) * scale.width, cap = CGFloat(text.capHeight) * scale.height
        let letterFont = Font(font.font(size: font.size(cap: cap, width: cell)) as CTFont)
        let arrows = font.arrows, arrowSize = arrows.size(cap: cap, width: cell)
        let arrowFont = Font(arrows.font(size: arrowSize) as CTFont), drop = arrows.arrowDrop * arrowSize
        let rgb = mono ? HiresImage.monoRGB
            : text.big ? HiresImage.colour(patternEven: text.patternEven, patternOdd: text.patternOdd) ?? .init(r: 0, g: 0, b: 0)
            : HiresImage.whiteRGB
        let colour = colour(rgb)
        var resolved: [String: (text: GraphicsContext.ResolvedText, size: CGSize, baseline: CGFloat)] = [:]
        for (letter, s) in zip(text.letters, characters) {
            guard let s else { continue }
            let r = resolved[s] ?? {
                let font = NativeLayer.arrowSigns.contains(s) ? arrowFont : letterFont
                let t = context.resolve(Text(s).font(font).foregroundStyle(colour))
                let m = t.measure(in: CGSize(width: 10_000, height: 10_000))
                return (t, m, t.firstBaseline(in: m))
            }()
            resolved[s] = r
            let centre = (CGFloat(letter.x) + CGFloat(text.cellWidth) / 2) * scale.width
            var baseline = CGFloat(HiresScreen.height - letter.y - text.descent) * scale.height
            if s == "←" || s == "→" { baseline += drop }
            var c = context
            c.translateBy(x: centre, y: baseline - r.baseline)
            // A shaft fills its cell and a little more, so the cells join.
            if s == DrawnText.shaft, r.size.width > 0 { c.scaleBy(x: cell * 1.1 / r.size.width, y: 1) }
            c.draw(r.text, in: CGRect(x: -r.size.width / 2, y: 0, width: r.size.width, height: r.size.height))
        }
    }

    /// The pixels a sprite covers: on the line of each row (from the bottom)
    /// each run of set bits, a bit two pixels across, bit 6 on the left.
    private func spans(_ sprite: LayerSprite) -> [(line: Int, from: Int, to: Int)] {
        var spans: [(line: Int, from: Int, to: Int)] = []
        for (r, bits) in sprite.rows.enumerated() {
            var bit = 6
            while bit >= 0 {
                guard bits >> bit & 1 != 0 else {
                    bit -= 1
                    continue
                }
                var last = bit
                while last > 0, bits >> (last - 1) & 1 != 0 { last -= 1 }
                spans.append((sprite.y + r, 2 * sprite.x + 2 * (6 - bit), 2 * sprite.x + 2 * (6 - last) + 2))
                bit = last - 1
            }
        }
        return spans
    }
}

/// Layer 3's sprites, plots and lines at the Apple's resolution, as their
/// drawings leave the pixels they cover (`add`, in the order drawn): lit where
/// their colour's patterns light them (by byte column, a bit a pixel), in the
/// colour the patterns show; cleared (black) elsewhere, and all of it where
/// they light none.  The colour screen shows an unlit pixel between two lit
/// ones in their colour (a colour lights every other pixel: two sprites side
/// by side make one body; white and a colour: the colour), so does `draw`;
/// the monochrome screen
/// the pixels lit, green.  Without the colour fringes: each pixel in its own
/// drawing's colour.  Each run of a colour on a line is one rectangle, a
/// colour's all filled at once, so they meet without seams.
private struct Pixels {
    let mono: Bool
    /// By pixel, top line first: 0 untouched (layer 2 shows), 1 cleared,
    /// else `colours[value - 2]`.
    private var pixels = [UInt8](repeating: 0, count: HiresScreen.width * HiresScreen.height)
    private var colours: [HiresImage.RGB] = []
    /// The lines touched (from the top).
    private var lines = Set<Int>()

    init(mono: Bool) {
        self.mono = mono
    }

    /// A drawing covering `spans` (on a line from the bottom, `from ..< to`
    /// across) in the colour of patterns `even` and `odd`.
    mutating func add(_ spans: [(line: Int, from: Int, to: Int)], even: UInt8, odd: UInt8) {
        let shown = HiresImage.colour(patternEven: even, patternOdd: odd)
        var lit: UInt8 = 1
        if let shown {
            let rgb = mono ? HiresImage.monoRGB : shown
            if let i = colours.firstIndex(of: rgb) {
                lit = UInt8(i + 2)
            } else {
                colours.append(rgb)
                lit = UInt8(colours.count + 1)
            }
        }
        for span in spans where (0 ..< HiresScreen.height).contains(span.line) {
            let line = HiresScreen.height - 1 - span.line, row = line * HiresScreen.width
            let from = max(span.from, 0), to = min(span.to, HiresScreen.width)
            guard from < to else { continue }
            lines.insert(line)
            for p in from ..< to {
                pixels[row + p] = (p / 7 & 1 == 0 ? even : odd) >> (p % 7) & 1 != 0 ? lit : 1
            }
        }
    }

    /// Draws the pixels and starts again.
    mutating func draw(in context: GraphicsContext, scale: CGSize) {
        guard !lines.isEmpty else { return }
        let w = HiresScreen.width
        var paths = [Path](repeating: Path(), count: colours.count + 2)
        for line in lines {
            let row = line * w
            if !mono {
                // An unlit pixel between two lit ones shows their colour (white
                // and a colour: the colour).
                let white = colours.firstIndex(of: HiresImage.whiteRGB).map { UInt8($0 + 2) }
                for p in 1 ..< w - 1 where pixels[row + p] < 2 {
                    let left = pixels[row + p - 1], right = pixels[row + p + 1]
                    if left >= 2, right >= 2 { pixels[row + p] = left == white ? right : left }
                }
            }
            var p = 0
            while p < w {
                let v = pixels[row + p]
                var end = p + 1
                while end < w, pixels[row + end] == v { end += 1 }
                if v != 0 {
                    paths[Int(v)].addRect(CGRect(x: CGFloat(p) * scale.width, y: CGFloat(line) * scale.height,
                                                 width: CGFloat(end - p) * scale.width, height: scale.height))
                }
                p = end
            }
            for p in 0 ..< w { pixels[row + p] = 0 }
        }
        context.fill(paths[1], with: .color(.black))
        for (i, rgb) in colours.enumerated() {
            context.fill(paths[i + 2], with: .color(Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)))
        }
        lines = []
        colours = []
    }
}
