import Foundation

/// A text DRAW_TEXT ($A2EA) drew: its letters where the routine puts them,
/// read from its parameters where it starts (CURRENT_TEXT_POINTER, _STYLE,
/// _COLOUR, _X, _Y), laid out as the 6502 code lays them out, the letters it
/// leaves out left out.  A drawing on layer 3 (`PageLayers`): the canvas
/// draws them in a modern font over the page drawn without them.
nonisolated struct DrawnText: Equatable {
    /// Style 2 is big text (DRAW_BIG_TEXT): the letters doubled in both
    /// directions and drawn in colour as sprites; every other style normal
    /// text, ORed into the page in white.
    let big: Bool
    /// Big text's patterns for even and odd byte columns
    /// (BIG_TEXT_PATTERN_EVEN/ODD by CURRENT_TEXT_COLOUR).
    let patternEven, patternOdd: UInt8
    let letters: [Letter]

    /// One letter: the Apple's character ($A1-$FF) and its cell's lower left
    /// corner: x in screen pixels (0-279), y the cell's bottom line counted
    /// from the bottom of the screen (0-191), as the engine counts.
    struct Letter: Equatable {
        let code: UInt8
        let x, y: Int
    }

    /// A cell's size in screen pixels: 7 × 8 (big: 14 × 16), with the
    /// capitals 7 (14) high above the bottom line (two lines) for the
    /// descenders.
    var cellWidth: Int { big ? 14 : 7 }
    var capHeight: Int { big ? 14 : 7 }
    var descent: Int { big ? 2 : 1 }

    /// The text DRAW_TEXT is about to draw, in `mem` where it starts.
    init(_ mem: [UInt8]) {
        big = mem[\.currentTextStyle] == 2
        let colour = Int(mem[\.currentTextColour])
        patternEven = mem[\.bigTextPatternEven, colour]
        patternOdd = mem[\.bigTextPatternOdd, colour]
        let x = mem[\.currentTextX], y = mem[\.currentTextY]
        let text = mem[\.currentTextPointer]
        // The string, to its 0 (a text without one ends where memory does).
        var bytes: [UInt8] = []
        var p = text
        while p < 0x10000, mem[p] != 0, bytes.count < 0x1000 {
            bytes.append(mem[p])
            p += 1
        }
        letters = big ? DrawnText.bigLetters(bytes, x: x, y: y) : DrawnText.normalLetters(bytes, x: x, y: y, mem)
    }

    /// Normal text ($A2FA): one byte column a letter, from x's byte column
    /// (x ≥ $8C: left of the screen, the column counted back from 0), every
    /// line 9 lower; a letter is drawn in columns 0-39 on lines below $B9
    /// only.  $A0 is a space, other bytes below $A1 start a new line.
    private static func normalLetters(_ bytes: [UInt8], x: UInt8, y: UInt8, _ mem: [UInt8]) -> [Letter] {
        let start: UInt8 = x < 0x8C ? mem[\.xByteTable, Int(x)] : 0 &- mem[\.xByteTable, Int(0 &- x)]
        var column = start, line = y
        var letters: [Letter] = []
        for c in bytes {
            if c >= 0xA0 {
                if c > 0xA0, column < 0x28, line < 0xB9 {
                    letters.append(Letter(code: c, x: 7 * Int(column), y: Int(line)))
                }
                column &+= 1
            } else {
                line &-= 9
                column = start
            }
        }
        return letters
    }

    /// Big text ($A3E1): each letter a sprite at (x, y) in object units (x
    /// two pixels), 7 units apart, every line ($8D) 18 lower; drawn where
    /// DRAW_SPRITE draws (x < $86, y < $B1).  $A0 is a space; other bytes
    /// are drawn as letters (below $A1 from what lies before the font: left
    /// out here).
    private static func bigLetters(_ bytes: [UInt8], x: UInt8, y: UInt8) -> [Letter] {
        var drawX = x, drawY = y
        var letters: [Letter] = []
        for c in bytes {
            if c == 0x8D {
                drawX = x
                drawY &-= 0x12
                continue
            }
            if c > 0xA0, drawX < 0x86, drawY < 0xB1 {
                letters.append(Letter(code: c, x: 2 * Int(drawX), y: Int(drawY)))
            }
            drawX &+= 7
        }
        return letters
    }
}

nonisolated extension DrawnText {
    /// What the canvas draws a hyphen in an arrow's shaft as: a line through
    /// the cell (`characters`).
    static let shaft = "─"

    /// What the canvas draws each letter of the texts as, by text and letter
    /// (nil: not drawn): the Apple's character (`character`); a hyphen in a
    /// run next to an arrow ({ or }) on its line as the arrow's `shaft`; a
    /// letter with an accent drawn over it by another text (Level 2's "Musé":
    /// a / five lines above the e) as the accented letter, its accent not
    /// drawn.
    static func characters(_ texts: [DrawnText]) -> [[String?]] {
        var characters = texts.map { text in text.letters.map { character($0.code) } as [String?] }
        for (i, text) in texts.enumerated() {
            for j in shafts(text) { characters[i][j] = shaft }
        }
        for (i, text) in texts.enumerated() where !text.big {
            marks: for (j, mark) in text.letters.enumerated() {
                guard let accent = accents[mark.code & 0x7F] else { continue }
                for (k, other) in texts.enumerated() where k != i && !other.big {
                    // A letter in the mark's column, its cell's bottom 1-7 lines below the mark's.
                    guard let l = other.letters.firstIndex(where: { $0.x == mark.x && (1 ..< 8).contains(mark.y - $0.y) }),
                          let base = characters[k][l] else { continue }
                    let accented = (base + accent).precomposedStringWithCanonicalMapping
                    guard accented.unicodeScalars.count == 1 else { continue }
                    characters[k][l] = accented
                    characters[i][j] = nil
                    continue marks
                }
            }
        }
        return characters
    }

    /// The Apple's character as text: its own signs as what they are,
    /// ← → ↑ ↓ for { } ~ and DEL, a bullet for ^, “ for ` (and ” for ", ’ for
    /// ', as its font draws them).
    static func character(_ code: UInt8) -> String {
        switch code & 0x7F {
        case 0x22: "”"
        case 0x27: "’"
        case 0x5E: "•"
        case 0x60: "“"
        case 0x7B: "←"
        case 0x7D: "→"
        case 0x7E: "↑"
        case 0x7F: "↓"
        default: String(UnicodeScalar(code & 0x7F))
        }
    }

    /// The accents a / or \ over a letter make (combining acute, grave).
    private static let accents: [UInt8: String] = [0x2F: "\u{301}", 0x5C: "\u{300}"]

    /// The letters (by index) that are hyphens in a run next to an arrow ({ or }) on its line.
    private static func shafts(_ text: DrawnText) -> Set<Int> {
        let hyphen: UInt8 = 0xAD, arrows: Set<UInt8> = [0xFB, 0xFD]
        let w = text.cellWidth
        var at: [Int: Int] = [:]                                // cell (x, y) → letter index
        for (i, l) in text.letters.enumerated() { at[l.y << 16 | l.x] = i }
        func code(_ x: Int, _ y: Int) -> UInt8? { at[y << 16 | x].map { text.letters[$0].code } }
        var shafts = Set<Int>()
        for (i, l) in text.letters.enumerated() where l.code == hyphen && !shafts.contains(i) {
            var left = l.x, right = l.x
            while code(left - w, l.y) == hyphen { left -= w }
            while code(right + w, l.y) == hyphen { right += w }
            guard arrows.contains(code(left - w, l.y) ?? 0) || arrows.contains(code(right + w, l.y) ?? 0) else { continue }
            for x in stride(from: left, through: right, by: w) { if let j = at[l.y << 16 | x] { shafts.insert(j) } }
        }
        return shafts
    }
}
