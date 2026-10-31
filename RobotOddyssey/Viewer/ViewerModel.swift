import SwiftUI
import UniformTypeIdentifiers

struct WorldGroup: Identifiable {
    let id: String
    let title: String
    let worlds: [World]
}

@Observable
final class ViewerModel {
    private(set) var disks: [DiskImage] = []
    private(set) var groups: [WorldGroup] = []
    private(set) var messages: [String] = []

    var selectedWorldID: World.ID? {
        didSet {
            if oldValue != selectedWorldID {
                thumbnails = [:]
                selectedObject = nil
                if let w = selectedWorld, !w.isRoomUsed(selectedRoom) {
                    selectedRoom = (0 ..< World.roomCount).first { w.isRoomUsed($0) } ?? 0
                }
            }
        }
    }
    var selectedRoom = 0 {
        didSet { if oldValue != selectedRoom { selectedObject = nil } }
    }
    var selectedObject: Int?
    var mode: HiresImage.Mode = .color {
        didSet { thumbnails = [:] }
    }
    var showEmptyRooms = false
    var showGrid = false

    /// Render caches; not observed, so filling them while a view draws is fine.
    @ObservationIgnored private var thumbnails: [Int: CGImage] = [:]
    @ObservationIgnored private var roomImage: (key: String, image: CGImage?)?

    static let diskTypes: [UTType] = [.folder, UTType(filenameExtension: "dsk") ?? .data, .data]

    var selectedWorld: World? {
        groups.lazy.flatMap(\.worlds).first { $0.id == selectedWorldID }
    }

    // MARK: loading

    func open(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls): open(urls: urls)
        case .failure(let error): messages = [error.localizedDescription]
        }
    }

    func open(urls: [URL]) {
        var found: [DiskImage] = []
        var problems: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            for file in diskFiles(at: url) {
                do {
                    found.append(try DiskImage(name: file.lastPathComponent, data: Data(contentsOf: file)))
                } catch {
                    problems.append(error.localizedDescription)
                }
            }
        }
        for d in found where !disks.contains(where: { $0.md5 == d.md5 }) {
            disks.append(d)
        }
        rebuild(extraMessages: problems)
        Bookmarks.save(urls)
    }

    func closeAll() {
        disks = []
        groups = []
        messages = []
        selectedWorldID = nil
        Bookmarks.clear()
    }

    func reopenLastDisks() {
        let urls = Bookmarks.load()
        if !urls.isEmpty { open(urls: urls) }
    }

    private func diskFiles(at url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.filter { ["dsk", "do"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Pair program disk sides by version, build all worlds, then the saved games.
    private func rebuild(extraMessages: [String]) {
        var notes = extraMessages
        var sets: [String: DiskSet] = [:]
        var storage: [DiskImage] = []
        for d in disks {
            switch d.role {
            case .programSide(let side, let version):
                var set = sets[version] ?? DiskSet(version: version)
                if side == .a, set.sideA == nil { set.sideA = d }
                if side == .b, set.sideB == nil { set.sideB = d }
                sets[version] = set
            case .storage:
                storage.append(d)
            case .unknown:
                notes.append("\(d.name): not recognized (only Robot Odyssey I v1.0/v1.1 is supported so far).")
            }
        }
        var newGroups: [WorldGroup] = []
        for (version, set) in sets.sorted(by: { $0.key > $1.key }) {
            let (worlds, errors) = WorldBuilder(disks: set).buildAll(idPrefix: "v\(version)/")
            notes += errors
            if set.sideA == nil { notes.append("v\(version): side A missing – Robotropolis levels unavailable.") }
            if set.sideB == nil { notes.append("v\(version): side B missing – tutorials and lab unavailable.") }
            newGroups.append(WorldGroup(id: version, title: set.title, worlds: worlds))
        }
        if let set = sets.sorted(by: { $0.key > $1.key }).first?.value {
            let reference = newGroups.first?.worlds.filter { $0.kind == .level || $0.kind == .lab } ?? []
            for disk in storage {
                let games = WorldBuilder(disks: set).savedGames(on: disk, reference: reference)
                newGroups.append(WorldGroup(id: "save:\(disk.md5)", title: "Saved games – \(disk.name)", worlds: games))
                if games.isEmpty { notes.append("\(disk.name): storage disk without saved games.") }
            }
        } else if !storage.isEmpty {
            notes.append("Open the program disk too, to view saved games.")
        }
        groups = newGroups
        messages = notes
        if selectedWorld == nil {
            selectedWorldID = groups.first?.worlds.first?.id
        }
    }

    // MARK: navigation

    func go(_ direction: Room.Direction) {
        guard let w = selectedWorld else { return }
        let target = w.room(selectedRoom).link(direction)
        if target != selectedRoom { selectedRoom = target }
    }

    // MARK: images

    func image(world: World, room: Int) -> CGImage? {
        let key = "\(world.id)#\(room)#\(mode.rawValue)"
        if let cached = roomImage, cached.key == key { return cached.image }
        let image = HiresImage.make(RoomRenderer(world: world).render(room: room), mode: mode)
        roomImage = (key, image)
        return image
    }

    func thumbnail(room: Int) -> CGImage? {
        if let t = thumbnails[room] { return t }
        guard let w = selectedWorld else { return nil }
        let t = HiresImage.make(RoomRenderer(world: w).render(room: room), mode: mode, scale: 1)
        thumbnails[room] = t
        return t
    }
}

/// Remembers the last opened disks (security-scoped bookmarks, macOS).
enum Bookmarks {
    private static let key = "lastDisks"

    static func save(_ urls: [URL]) {
        #if os(macOS)
        let known = Set(load().map(\.standardizedFileURL))
        var data = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        for url in urls where !known.contains(url.standardizedFileURL) {
            if let b = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
                data.append(b)
            }
        }
        UserDefaults.standard.set(data, forKey: key)
        #endif
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func load() -> [URL] {
        #if os(macOS)
        let data = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        return data.compactMap {
            var stale = false
            return try? URL(resolvingBookmarkData: $0, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        }
        #else
        return []
        #endif
    }
}
