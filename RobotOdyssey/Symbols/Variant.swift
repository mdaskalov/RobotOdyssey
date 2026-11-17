import Apple2Kit
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

    /// The engine's symbols, for data: the versions keep it in the same
    /// places (only code in the language card's $D000 bank moved).
    var symbols: any EngineSymbols {
        Variant(engine: self, version: .v1_1).symbols
    }
}

/// The program disks' version, as the loader's file table tells (`LoaderSymbols`).
nonisolated enum Version: String, CaseIterable {
    case v1_0 = "1.0", v1_1 = "1.1"
}

/// What a world's symbols' addresses depend on: its engine and the disks'
/// version.  Each has its symbol map (`symbols`): the engine's class, made
/// for the version.
nonisolated struct Variant: Hashable, CustomStringConvertible {
    let engine: EngineBuild
    let version: Version

    static var all: [Variant] {
        EngineBuild.allCases.flatMap { e in Version.allCases.map { Variant(engine: e, version: $0) } }
    }

    /// The symbols of a world of this engine and version: `GameSymbols` with
    /// the engine's own (`LevelsSymbols`, `KitSymbols`, `LabSymbols`).
    var symbols: any EngineSymbols {
        Variant.maps[engine.rawValue * 2 + (version == .v1_1 ? 0 : 1)]
    }

    /// Each variant's map, made once: v1.1 then v1.0 for each engine.
    private static let maps: [any EngineSymbols] = EngineBuild.allCases.flatMap { engine in
        [Version.v1_1, .v1_0].map { version -> any EngineSymbols in
            switch engine {
            case .levels: LevelsSymbols(version)
            case .kit: KitSymbols(version)
            case .lab: LabSymbols(version)
            }
        }
    }

    var description: String { "\(engine) v\(version.rawValue)" }
}

/// Sprite data: 16 rows from the address, row 0 at the bottom (or several
/// sprites in a row).  The game's own kind of symbol, beside Apple2Kit's
/// `Byte`, `Word`, `Table` and `Routine`.
nonisolated struct Sprite: Symbol {
    let address: Int
    let guess: Bool
}
