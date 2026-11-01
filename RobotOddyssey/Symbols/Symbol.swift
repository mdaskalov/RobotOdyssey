import Foundation

/// The engine a world runs: the engine files the loader loads with it
/// (`GameCatalog`).  The three are the same code, assembled with their
/// variables, tables and sprites in other places; engine main ($9500-$B7D6)
/// is one file for all of them (Docs/Symbols.md).
nonisolated enum EngineBuild: Int, CaseIterable {
    /// The Robotropolis levels 1-5 (side A).
    case levels
    /// Robot Anatomy and Toolkit (side B).
    case kit
    /// The Innovation Lab and its tutorial (side B).
    case lab
}

/// The program disks' version, as the loader's file table tells (`LoaderSymbols`).
nonisolated enum Version: String, CaseIterable {
    case v1_0 = "1.0", v1_1 = "1.1"
}

/// What a world's symbols' addresses depend on: its engine and the disks' version.
nonisolated struct Variant: Hashable, CustomStringConvertible {
    let engine: EngineBuild
    let version: Version

    /// Position in `Address`'s list: v1.1 then v1.0 for each engine.
    fileprivate var index: Int { engine.rawValue * 2 + (version == .v1_1 ? 0 : 1) }

    static var all: [Variant] {
        EngineBuild.allCases.flatMap { e in Version.allCases.map { Variant(engine: e, version: $0) } }
    }

    var description: String { "\(engine) v\(version.rawValue)" }
}

/// Where a symbol is in each variant: the same everywhere, or per engine
/// (nil: not in that engine), with v1.0's place where its code moved.  Only
/// the language card's $D000 bank differs between the versions.
nonisolated struct Address: Equatable {
    /// One per variant in `Variant.index` order (-1: none), kept inline: the
    /// native routines look addresses up on every access.
    private let places: SIMD8<Int32>
    /// The address if it is the same in every variant.
    let everywhere: Int?

    init(_ everywhere: Int) {
        places = SIMD8(repeating: Int32(everywhere))
        self.everywhere = everywhere
    }

    init(levels: Int?, kit: Int?, lab: Int?, levelsV1_0: Int? = nil, kitV1_0: Int? = nil, labV1_0: Int? = nil) {
        let p = [levels, levelsV1_0 ?? levels, kit, kitV1_0 ?? kit, lab, labV1_0 ?? lab, nil, nil].map { Int32($0 ?? -1) }
        places = SIMD8(p)
        everywhere = nil
    }

    /// The address in `v`, nil if the variant has no such symbol.
    @inline(__always)
    func callAsFunction(_ v: Variant) -> Int? {
        let a = places[v.index]
        return a < 0 ? nil : Int(a)
    }

    /// The address in `engine`, for data, which the versions keep in the same
    /// places (only code in the $D000 bank moved).
    func callAsFunction(_ engine: EngineBuild) -> Int? {
        self(Variant(engine: engine, version: .v1_1))
    }
}

/// A named place in memory.  Its name is the property's in a symbol map
/// (`GameSymbols`, `LoaderSymbols`, `Level1Symbols`), in capitals in the
/// Mariani .sym files: `moveDX` is MOVE_DX.
nonisolated protocol Symbol {
    var address: Address { get }
    /// The name is a guess (`_Q` in the .sym files).
    var guess: Bool { get }
    init(address: Address, guess: Bool)
}

nonisolated extension Symbol {
    /// At the same address in every world and version.
    init(_ address: Int, guess: Bool = false) {
        self.init(address: Address(address), guess: guess)
    }

    /// Per engine (nil where an engine has none), and where v1.0 has it elsewhere.
    init(levels: Int? = nil, kit: Int? = nil, lab: Int? = nil,
         levelsV1_0: Int? = nil, kitV1_0: Int? = nil, labV1_0: Int? = nil, guess: Bool = false) {
        self.init(address: Address(levels: levels, kit: kit, lab: lab, levelsV1_0: levelsV1_0, kitV1_0: kitV1_0, labV1_0: labV1_0),
                  guess: guess)
    }
}

/// One byte: a variable or a constant.
nonisolated struct Byte: Symbol {
    let address: Address
    let guess: Bool
}

/// Two bytes, low byte first: a pointer or a vector.
nonisolated struct Word: Symbol {
    let address: Address
    let guess: Bool
}

/// Bytes indexed from the address: an array of the engine's or the world's.
nonisolated struct Table: Symbol {
    let address: Address
    let guess: Bool
}

/// Sprite data: 16 rows from the address, row 0 at the bottom (or several sprites in a row).
nonisolated struct Sprite: Symbol {
    let address: Address
    let guess: Bool
}

/// Code at an entry point.  A routine that a native replaces has its `code`:
/// the bytes from its entry (variables left out) and their MD5, per variant.
/// The loader checks them (`CodeCheck`), so a native only ever replaces the
/// exact code it was ported from.
nonisolated struct Routine: Symbol {
    let address: Address
    let guess: Bool
    let code: [Code]

    init(address: Address, guess: Bool) {
        self.init(address: address, guess: guess, code: [])
    }

    init(address: Address, guess: Bool, code: [Code]) {
        self.address = address
        self.guess = guess
        self.code = code
    }

    /// Engine main code: the same in every world and version.
    init(_ entry: Int, code: Range<Int>..., md5: String) {
        self.init(address: Address(entry), guess: false, code: [Code(engines: EngineBuild.allCases, version: nil, ranges: code, md5: md5)])
    }

    /// Per engine, with the code of each.
    init(levels: Int? = nil, kit: Int? = nil, lab: Int? = nil, levelsV1_0: Int? = nil, code: [Code]) {
        self.init(address: Address(levels: levels, kit: kit, lab: lab, levelsV1_0: levelsV1_0), guess: false, code: code)
    }

    /// Where it is in `v`: its entry point, if the variant has the routine.
    func entry(_ v: Variant) -> UInt16? {
        address(v).map { UInt16($0) }
    }

    /// The fingerprint of the routine's code in `v`, if it has one there.
    func code(in v: Variant) -> Code? {
        guard address(v) != nil else { return nil }
        return code.first { $0.engines.contains(v.engine) && ($0.version ?? v.version) == v.version }
    }

    /// Whether `mem` (language card bank 2 mapped) holds the routine's code as
    /// in `v`; nil where it has no fingerprint (not ported there).
    func matches(_ mem: [UInt8], _ v: Variant) -> Bool? {
        code(in: v).map { $0.matches(mem) }
    }
}

/// A routine's code in some variants: address ranges and the MD5 of their bytes.
nonisolated struct Code {
    let engines: [EngineBuild]
    /// nil: both versions.
    let version: Version?
    let ranges: [Range<Int>]
    let md5: String

    static func levels(_ ranges: Range<Int>..., md5: String) -> Code {
        Code(engines: [.levels], version: nil, ranges: ranges, md5: md5)
    }

    static func levels(_ version: Version, _ ranges: Range<Int>..., md5: String) -> Code {
        Code(engines: [.levels], version: version, ranges: ranges, md5: md5)
    }

    static func kit(_ ranges: Range<Int>..., md5: String) -> Code {
        Code(engines: [.kit], version: nil, ranges: ranges, md5: md5)
    }

    static func lab(_ ranges: Range<Int>..., md5: String) -> Code {
        Code(engines: [.lab], version: nil, ranges: ranges, md5: md5)
    }

    /// MD5 of these ranges of `mem`.
    func digest(_ mem: [UInt8]) -> String {
        DiskImage.md5(ranges.flatMap { mem[$0] })
    }

    func matches(_ mem: [UInt8]) -> Bool { digest(mem) == md5 }
}

// MARK: names

/// A symbol map's symbols with their names, in declaration order.
nonisolated func namedSymbols(of map: Any) -> [(name: String, symbol: Symbol)] {
    Mirror(reflecting: map).children.compactMap { child in
        guard let label = child.label, let s = child.value as? Symbol else { return nil }
        return (symbolName(label, guess: s.guess), s)
    }
}

/// The .sym name of a property: `moveDX` MOVE_DX, `drawRobot2Scan`
/// DRAW_ROBOT2_SCAN, `engDA44` ENG_DA44 (a trailing address after a
/// lower-case letter), `_Q` for a guess.
nonisolated func symbolName(_ property: String, guess: Bool = false) -> String {
    let c = Array(property)
    var end = c.count
    if c.count > 4, c[(c.count - 4)...].allSatisfy({ $0.isHexDigit && !$0.isLowercase }), c[c.count - 5].isLowercase {
        end = c.count - 4
    }
    var name = ""
    for i in 0 ..< end {
        if i > 0, c[i].isUppercase,
           c[i - 1].isLowercase || c[i - 1].isNumber || (c[i - 1].isUppercase && i + 1 < end && c[i + 1].isLowercase) {
            name += "_"
        }
        name += c[i].uppercased()
    }
    if end < c.count { name += "_" + String(c[end...]) }
    return guess ? name + "_Q" : name
}
