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
    var renderer: Renderer = .game {
        didSet { thumbnails = [:] }
    }
    var showEmptyRooms = false
    var showGrid = false

    /// Render caches; not observed, so filling them while a view draws is fine.
    @ObservationIgnored private var thumbnails: [Int: CGImage] = [:]
    @ObservationIgnored private var roomImage: (key: String, image: CGImage?)?
    /// Each world after its start-up code ran (nil: it could not run).
    @ObservationIgnored private var gameScreens: [World.ID: GameScreen?] = [:]
    @ObservationIgnored private var renderErrors: [String: String] = [:]

    enum Renderer: String, CaseIterable, Identifiable {
        /// The world's own draw phase on the 6502 emulator, with the native engine routines.
        case game = "Game"
        /// RoomRenderer: tiles, texts, objects and wires only.
        case staticRooms = "Static"
        var id: String { rawValue }
    }

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

    /// Pair program disk sides (same version, same file name apart from the side
    /// letter/digit, e.g. ROBOT-1/ROBOT-2), build all worlds, then the saved games.
    private func rebuild(extraMessages: [String]) {
        var notes = extraMessages
        var sets: [String: DiskSet] = [:]
        var storage: [DiskImage] = []
        for d in disks {
            switch d.role {
            case .programSide(let side, let version):
                let key = "\(version)|\(ViewerModel.stem(d.name))"
                var set = sets[key] ?? DiskSet(version: version)
                if side == .a, set.sideA == nil { set.sideA = d }
                if side == .b, set.sideB == nil { set.sideB = d }
                sets[key] = set
            case .storage:
                storage.append(d)
            case .unknown:
                notes.append("\(d.name): not recognized (only Robot Odyssey I v1.0/v1.1 is supported so far).")
            }
        }
        // Single sides with differently named partners of the same version belong together.
        for (key, set) in sets where set.sideB == nil {
            if let (otherKey, other) = sets.first(where: { $0.key != key && $0.value.sideA == nil && $0.value.version == set.version }) {
                sets[key]?.sideB = other.sideB
                sets[otherKey] = nil
            }
        }
        var newGroups: [WorldGroup] = []
        let ordered = sets.sorted { ($0.value.version, $1.key) > ($1.value.version, $0.key) }
        for (key, set) in ordered {
            let (worlds, errors) = WorldBuilder(disks: set).buildAll(idPrefix: "\(key)/")
            notes += errors
            if set.sideA == nil { notes.append("\(set.title): side A missing – Robotropolis levels unavailable.") }
            if set.sideB == nil { notes.append("\(set.title): side B missing – tutorials and lab unavailable.") }
            newGroups.append(WorldGroup(id: key, title: set.title, worlds: worlds))
        }
        if let (key, set) = ordered.first(where: { $0.value.sideA != nil }) {
            let reference = newGroups.first { $0.id == key }?.worlds.filter { $0.kind == .level || $0.kind == .lab } ?? []
            for disk in storage {
                let games = WorldBuilder(disks: set).savedGames(on: disk, reference: reference)
                newGroups.append(WorldGroup(id: "save:\(disk.md5)", title: "Saved games – \(disk.name)", worlds: games))
                if games.isEmpty { notes.append("\(disk.name): storage disk without saved games.") }
            }
        } else if !storage.isEmpty {
            notes.append("Open the program disk too, to view saved games.")
        }
        gameScreens = [:]
        renderErrors = [:]
        groups = newGroups
        messages = notes
        if selectedWorld == nil {
            selectedWorldID = groups.first?.worlds.first?.id
        }
    }

    /// File name without extension and without a trailing side marker (a/b/1/2).
    static func stem(_ name: String) -> String {
        var s = (name as NSString).deletingPathExtension
        if let last = s.last, "aAbB12".contains(last) { s.removeLast() }
        return s
    }

    // MARK: navigation

    func go(_ direction: Room.Direction) {
        guard let w = selectedWorld else { return }
        let target = w.room(selectedRoom).link(direction)
        if target != selectedRoom { selectedRoom = target }
    }

    // MARK: images

    func image(world: World, room: Int) -> CGImage? {
        let key = "\(world.id)#\(room)#\(mode.rawValue)#\(renderer.rawValue)"
        if let cached = roomImage, cached.key == key { return cached.image }
        let image = HiresImage.make(screen(world: world, room: room), mode: mode)
        roomImage = (key, image)
        return image
    }

    func thumbnail(room: Int) -> CGImage? {
        if let t = thumbnails[room] { return t }
        guard let w = selectedWorld else { return nil }
        let t = HiresImage.make(screen(world: w, room: room), mode: mode, scale: 1)
        thumbnails[room] = t
        return t
    }

    /// The room as the chosen renderer draws it; the game's code falls back to the static renderer.
    private func screen(world: World, room: Int) -> HiresScreen {
        if renderer == .game, world.codeRooms[room] == nil, let game = gameScreen(world) {
            do {
                return try game.render(room: room).screen
            } catch {
                renderErrors["\(world.id)#\(room)"] = error.localizedDescription
            }
        }
        return RoomRenderer(world: world).render(room: room)
    }

    private func gameScreen(_ world: World) -> GameScreen? {
        if let cached = gameScreens[world.id] { return cached }
        do {
            let screen = try GameScreen(world: world)
            gameScreens[world.id] = screen
            return screen
        } catch {
            gameScreens[world.id] = .some(nil)
            renderErrors[world.id] = error.localizedDescription
            return nil
        }
    }

    /// How the room in the canvas was drawn.
    func renderNote(world: World, room: Int) -> String {
        guard renderer == .game else { return "Static renderer: tiles, texts, objects and wires" }
        if world.codeRooms[room] != nil { return "Code room – drawn as walls by the static renderer" }
        if let e = renderErrors["\(world.id)#\(room)"] ?? renderErrors[world.id] {
            return "The game's code could not draw this room (\(e)) – static renderer"
        }
        guard let game = gameScreen(world) else { return "" }
        let natives = game.natives.isEmpty ? "none" : game.natives.joined(separator: ", ")
        return String(format: "Drawn by the world's code ($%04X–$%04X) on the 6502 emulator · native: %@",
                      game.phase.start, game.phase.end, natives)
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
