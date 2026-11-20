import Apple2Kit
import Foundation
import MOS6502

/// The loader's texts on the native layer (Docs/Loader.md): its messages,
/// prompts and directories are CHAR_OUT's letters ($4F06, boot stage 2), one
/// a call, each overwriting its 7 × 8 cell.  Like the engine's DRAW_TEXT it
/// is followed as 6502 code (`Machine.followLayers`, while the loader runs):
/// where it starts, the letter it is about to draw goes on layer 3
/// (`charOutLetter`), drawn by the canvas in its font, and the page is drawn
/// as ever.  Its letters own their cells (`PageLayers.textsOwnCells`): one
/// written over is gone, as on the Apple.  Spaces, controls, inverse and
/// the input's cursor (a block) stay the Apple's pixels, and so does every
/// letter with CHAR_OUT switched off.  CLEAR_SCREEN empties page 1's layer 3.
/// Followed only where CHAR_OUT's code is the loader's (its fingerprint:
/// the same in every v1.0 and v1.1 dump).
nonisolated extension Loader {
    /// CHAR_OUT's name: its switch.
    static let charOutName = LoaderSymbols.name(of: \.charOut)
    static let charOutEntry = UInt16(LoaderSymbols.address(\.charOut))
    /// Where page 1's drawing starts again: CLEAR_SCREEN clears it.
    static let clearScreenEntry = UInt16(LoaderSymbols.address(\.clearScreen))

    /// CHAR_OUT's drawing on layer 3, looked at where it starts: the letter
    /// in A, on the page CHAR_PAGE selects.
    static func charOutDrawing() -> Native.Drawing {
        let code = Fingerprint(\.charOut)
        func letter(_ cpu: CPU6502) -> DrawnText.Letter? {
            guard code.matches(cpu.mem) else { return nil }
            return cpu.withRAM(LoaderSymbols.map) { charOutLetter(cpu.a, $0) }
        }
        return Native.Drawing(draws: { letter($0) != nil },
                              item: { cpu in letter(cpu).map { .text(DrawnText(letters: [$0])) } },
                              page: { cpu in cpu.withRAM(LoaderSymbols.map) { $0.charPage & 0x40 != 0 ? 1 : 0 } })
    }

    /// The letter CHAR_OUT draws for `code` (`m` where it starts), where it
    /// draws it: $A1-$FF in normal text (not inverse, not a block) at the
    /// cursor, moved to the next row first where the column is past the
    /// window's width, and to the window's top row from below its last, as
    /// CHAR_PRINT moves it.  nil for the rest (a space, a control: the
    /// Apple's pixels) and for a cell off the screen.
    static func charOutLetter(_ code: UInt8, _ m: LoaderRAM) -> DrawnText.Letter? {
        guard code > 0xA0, m.charInverse == 0, m.charBlock & 0x80 == 0 else { return nil }
        var column = m.cursorColumn, row = m.cursorRow
        if column &+ 1 > m.windowWidth {
            column = 0
            row &+= 1
            if row >= m.windowBottom { row = m.windowTop }
        }
        if row &+ 1 > m.windowBottom {
            column = 0
            row = m.windowTop
        }
        let x = Int(m.windowLeft) + Int(column)
        guard x < HiresScreen.bytesPerLine, Int(row) < HiresScreen.height / 8 else { return nil }
        // Row r's cell: lines 8r (top) to 8r + 7, its bottom line counted from the bottom of the screen.
        return DrawnText.Letter(code: code, x: 7 * x, y: HiresScreen.height - 8 - 8 * Int(row))
    }
}
