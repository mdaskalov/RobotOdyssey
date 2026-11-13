import Apple2Kit
import SwiftUI
#if os(macOS)
typealias PlatformFont = NSFont
#else
typealias PlatformFont = UIFont
#endif

/// The fonts the native layer's texts can take: monospaced ones, as the
/// game's letters are, which macOS has (`NativeLayer.font`: SF Mono Medium,
/// till a settings menu chooses).
enum TextFont: String, CaseIterable, Identifiable {
    case sfMono = "SF Mono", sfMonoMedium = "SF Mono Medium", menlo = "Menlo", monaco = "Monaco"
    case ptMono = "PT Mono", andaleMono = "Andale Mono", courierNew = "Courier New"

    var id: String { rawValue }

    func font(size: CGFloat) -> PlatformFont {
        switch self {
        case .sfMono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .sfMonoMedium: return .monospacedSystemFont(ofSize: size, weight: .medium)
        default:
            let name = [TextFont.menlo: "Menlo-Regular", .monaco: "Monaco", .ptMono: "PTMono-Regular",
                        .andaleMono: "AndaleMono", .courierNew: "CourierNewPSMT"][self]
            return name.flatMap { PlatformFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
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
/// (`LayerItem`), drawn by the Mac at its resolution over the Apple's pixels,
/// in the order drawn, in the engine's coordinates scaled to the canvas.
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
///   VERTICAL_LINE) as the Apple's pixels: drawn on layer 2 as their routines
///   draw them, with what was written between them, in order, and coloured
///   by the one function that colours the Apple's pixels (`LayerPixels`,
///   `Screen.image`): the image under this layer (`pixels`).  The same pixels
///   as with their routines switched off.  What was drawn after a text lies
///   over it: that image again there (`afterTexts`).  Where new drawings of
///   the sprites come in.
struct NativeLayer: View, Equatable {
    /// The texts' font.
    static let font = TextFont.sfMonoMedium

    let items: [LayerItem]
    /// The Apple's pixels of layers 2 and 3 (`LayerPixels`), the image under
    /// this layer.
    let pixels: CGImage?
    /// By dot, how many texts came before what was drawn there
    /// (`LayerPixels.afterTexts`).
    let afterTexts: [UInt8]
    let mono: Bool

    static func == (a: NativeLayer, b: NativeLayer) -> Bool {
        a.mono == b.mono && a.pixels === b.pixels && a.items == b.items && a.afterTexts == b.afterTexts
    }

    var body: some View {
        Canvas { context, size in
            let scale = CGSize(width: size.width / CGFloat(HiresScreen.width), height: size.height / CGFloat(HiresScreen.height))
            let texts = items.compactMap { item -> DrawnText? in if case .text(let t) = item { t } else { nil } }
            guard !texts.isEmpty else { return }
            let characters = DrawnText.characters(texts)
            let over = drawnAfter(size: size)
            let image = pixels.map { Image(decorative: $0, scale: 1).interpolation(.none) }
            for (t, text) in texts.enumerated() {
                draw(text, characters[t], in: context, scale: scale)
                // What was drawn after this text and before the next: over it.
                if t + 1 < over.count, !over[t + 1].isEmpty, let image {
                    var c = context
                    c.clip(to: over[t + 1])
                    c.draw(image, in: CGRect(origin: .zero, size: size))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The dots drawn after each number of texts: [n] those after n texts
    /// (from 1), each run of them on a line one rectangle.
    private func drawnAfter(size: CGSize) -> [Path] {
        guard !afterTexts.isEmpty else { return [] }
        let w = HiresScreen.dotsPerLine
        let scale = CGSize(width: size.width / CGFloat(w), height: size.height / CGFloat(HiresScreen.height))
        var paths: [Path] = []
        for line in 0 ..< HiresScreen.height {
            let row = line * w
            var p = 0
            while p < w {
                let n = Int(afterTexts[row + p])
                var end = p + 1
                while end < w, afterTexts[row + end] == afterTexts[row + p] { end += 1 }
                if n > 0 {
                    while paths.count <= n { paths.append(Path()) }
                    paths[n].addRect(CGRect(x: CGFloat(p) * scale.width, y: CGFloat(line) * scale.height,
                                            width: CGFloat(end - p) * scale.width, height: scale.height))
                }
                p = end
            }
        }
        return paths
    }

    private func colour(_ rgb: Screen.RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    private static let arrowSigns: Set<String> = ["←", "→", "↑", "↓", DrawnText.shaft]

    private func draw(_ text: DrawnText, _ characters: [String?], in context: GraphicsContext, scale: CGSize) {
        let font = NativeLayer.font
        let cell = CGFloat(text.cellWidth) * scale.width, cap = CGFloat(text.capHeight) * scale.height
        let letterFont = Font(font.font(size: font.size(cap: cap, width: cell)) as CTFont)
        let arrows = font.arrows, arrowSize = arrows.size(cap: cap, width: cell)
        let arrowFont = Font(arrows.font(size: arrowSize) as CTFont), drop = arrows.arrowDrop * arrowSize
        let rgb = mono ? Screen.monoRGB
            : text.big ? Screen.colour(patternEven: text.patternEven, patternOdd: text.patternOdd) ?? .init(r: 0, g: 0, b: 0)
            : Screen.whiteRGB
        let colour = colour(rgb)
        // Big text's palette bit (every byte it draws) shows it half a pixel to the right.
        let shift: CGFloat = text.big && text.patternEven & 0x80 != 0 ? 0.5 : 0
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
            let centre = (CGFloat(letter.x) + CGFloat(text.cellWidth) / 2 + shift) * scale.width
            var baseline = CGFloat(HiresScreen.height - letter.y - text.descent) * scale.height
            if s == "←" || s == "→" { baseline += drop }
            var c = context
            c.translateBy(x: centre, y: baseline - r.baseline)
            // A shaft fills its cell and a little more, so the cells join.
            if s == DrawnText.shaft, r.size.width > 0 { c.scaleBy(x: cell * 1.1 / r.size.width, y: 1) }
            c.draw(r.text, in: CGRect(x: -r.size.width / 2, y: 0, width: r.size.width, height: r.size.height))
        }
    }
}
