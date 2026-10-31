import Foundation
import CryptoKit

/// A 140K Apple II disk image (.dsk / .do, DOS 3.3 sector order).
///
/// Robot Odyssey does not use DOS; its loader reads whole tracks and puts the
/// k-th 256-byte page of a track at consecutive memory pages.  We address the
/// disk by "page" = track * 16 + k, matching the game's own loader table.
struct DiskImage {
    static let size = 35 * 16 * 256

    /// .dsk sector holding the k-th page of a track, as read by the game's loader.
    static let trackPageOrder = [0x0, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0xF, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7]

    let name: String
    let data: [UInt8]
    let md5: String

    init(name: String, data: Data) throws {
        guard data.count == DiskImage.size else { throw DiskError.notADiskImage(name) }
        self.name = name
        self.data = [UInt8](data)
        md5 = DiskImage.md5(data)
    }

    static func md5<D: DataProtocol>(_ data: D) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func page(_ n: Int) -> ArraySlice<UInt8> {
        let track = n / 16, k = n % 16
        let offset = track * 4096 + DiskImage.trackPageOrder[k] * 256
        return data[offset ..< offset + 256]
    }

    /// `length` bytes starting at page `first`.
    func read(page first: Int, length: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(length)
        var p = first
        while out.count < length {
            out += page(p).prefix(length - out.count)
            p += 1
        }
        return out
    }
}

enum DiskError: LocalizedError {
    case notADiskImage(String)
    case missingSide(String)
    case exitCodeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notADiskImage(let n): "\(n) is not a 140K Apple II disk image."
        case .missingSide(let s): "Side \(s) of the program disk is needed."
        case .exitCodeNotFound(let w): "Could not find the exit code of \(w)."
        }
    }
}
