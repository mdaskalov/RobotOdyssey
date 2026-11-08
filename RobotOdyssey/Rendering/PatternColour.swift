import Apple2Kit

nonisolated extension Screen {
    /// The colour a pair of patterns (even and odd byte columns, as the
    /// sprites and big text take them) shows filled in: white where pixels of
    /// both column parities are on, a palette colour where only one; nil:
    /// black.
    static func colour(patternEven: UInt8, patternOdd: UInt8) -> RGB? {
        var parities = Set<Int>()
        for (column, pattern) in [patternEven, patternOdd].enumerated() {
            for bit in 0 ..< 7 where pattern >> bit & 1 != 0 { parities.insert((column * 7 + bit) & 1) }
        }
        guard let parity = parities.first else { return nil }
        return parities.count == 2 ? whiteRGB : hiresRGB[Int(patternEven >> 6 & 2) + parity]
    }
}
