import Foundation

/// The disk drive (slot 6, drive 1) with the disks the game asks for: the
/// program disk's two sides of one version and a storage disk for saved games
/// and chips.  The loader reads and writes it through RWTS (`Loader.rwts`),
/// sector by sector by track and the loader's sector number, which is a
/// page's place in its track (`DiskImage.page`), and tells the disks apart
/// by the side number in their boot sector (READ_SIDE_ID).  The program disk
/// is write-protected, as the originals are; what the game writes on the
/// storage disk stays in `storage` for the app to keep (`takeWritten`).
nonisolated final class DiskDrive {
    /// A disk by the side number in its boot sector (byte $FB, with $FC =
    /// $FB EOR $A5): the program disk's sides, 0 and 1 (side 1 and side 2 on
    /// the labels), and a storage disk, 2.
    enum Disk: Int, CaseIterable {
        case sideA, sideB, storage
    }

    /// The name of the storage disk the drive makes when it has none.
    static let storageName = "save.dsk"

    /// RWTS's return codes in the IOB.
    static let writeProtected: UInt8 = 0x10
    static let driveError: UInt8 = 0x40

    let program: DiskSet
    /// The storage disk as the game left it; nil until the loader asks for
    /// one if none was given, then a blank one (`insert`).
    private(set) var storage: (name: String, bytes: [UInt8])?
    /// The disk in the drive.
    private(set) var inserted: Disk?
    /// The storage disk changed since the last `takeWritten`.
    private var written = false

    /// `inserted` if there, else a program side that is.
    init(program: DiskSet, storage: DiskImage?, inserted: Disk) {
        self.program = program
        self.storage = storage.map { ($0.name, $0.data) }
        if !insert(inserted) {
            insert(program.sideA != nil ? .sideA : .sideB)
        }
    }

    /// Puts `disk` in the drive; a storage disk is made, blank, if there is
    /// none.  False if the disk isn't there (a side not loaded): the drive
    /// keeps its disk.
    @discardableResult
    func insert(_ disk: Disk) -> Bool {
        switch disk {
        case .sideA, .sideB:
            guard program.disk(disk == .sideA ? .a : .b) != nil else { return false }
        case .storage:
            if storage == nil {
                guard let side = program.sideA ?? program.sideB else { return false }
                storage = (DiskDrive.storageName, DiskDrive.blankStorage(from: side))
            }
        }
        inserted = disk
        return true
    }

    /// The name of `disk`'s image, nil if it isn't there.
    func name(of disk: Disk) -> String? {
        switch disk {
        case .sideA: program.sideA?.name
        case .sideB: program.sideB?.name
        case .storage: storage?.name
        }
    }

    /// The whole of the disk in the drive, in DOS order (as a .dsk).
    private var image: [UInt8]? {
        switch inserted {
        case .sideA: program.sideA?.data
        case .sideB: program.sideB?.data
        case .storage: storage?.bytes
        case nil: nil
        }
    }

    /// Track 0 of the disk in the drive, its 16 sectors in DOS order, as boot
    /// stage 1 reads them.
    var trackZero: [UInt8]? {
        image.map { Array($0[0 ..< 16 * 256]) }
    }

    // MARK: RWTS

    /// A sector of the disk in the drive; nil: no disk.
    func read(track: Int, sector: Int) -> [UInt8]? {
        guard let image else { return nil }
        let offset = DiskImage.offset(page: track * 16 + sector)
        return Array(image[offset ..< offset + 256])
    }

    /// Writes a sector; RWTS's return code (0: written).
    func write(track: Int, sector: Int, bytes: [UInt8]) -> UInt8 {
        guard inserted == .storage, storage != nil else { return inserted == nil ? DiskDrive.driveError : DiskDrive.writeProtected }
        let offset = DiskImage.offset(page: track * 16 + sector)
        storage!.bytes.replaceSubrange(offset ..< offset + 256, with: bytes)
        written = true
        return 0
    }

    /// Formats the disk: the storage disk, all sectors zero (the loader's
    /// NEW_STORAGE_DISK asks for a blank disk and warns that it will be erased;
    /// the app's blank disk is its storage disk).
    func format() -> UInt8 {
        guard insert(.storage) else { return DiskDrive.driveError }
        storage!.bytes = [UInt8](repeating: 0, count: DiskImage.size)
        written = true
        return 0
    }

    /// The storage disk if the game wrote on it since the last call.
    func takeWritten() -> DiskImage? {
        guard written, let storage else { return nil }
        written = false
        return try? DiskImage(name: storage.name, bytes: storage.bytes)
    }

    /// A storage disk as the loader makes one (NEW_STORAGE_DISK): formatted,
    /// all zero, with its boot sector, STORAGE_BOOT (the program disk's track
    /// 0 sector 6, with side number 2), and empty game and chip directories
    /// (pages 32 and 33 of spaces).  The same as the blank storage disk
    /// DATAV11.DSK.
    static func blankStorage(from program: DiskImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: DiskImage.size)
        bytes.replaceSubrange(0 ..< 256, with: program.data[6 * 256 ..< 7 * 256])
        for page in [32, 33] {
            let offset = DiskImage.offset(page: page)
            bytes.replaceSubrange(offset ..< offset + 256, with: repeatElement(0xA0, count: 256))
        }
        return bytes
    }
}
