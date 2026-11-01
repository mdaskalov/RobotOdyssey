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
        didSet {
            if oldValue != selectedRoom {
                selectedObject = nil
                showLive()
            }
        }
    }
    var selectedObject: Int?
    var mode: HiresImage.Mode = .color {
        didSet {
            thumbnails = [:]
            showLive()
        }
    }
    var renderer: Renderer = .game {
        didSet { thumbnails = [:] }
    }
    var showEmptyRooms = false
    var showGrid = false

    /// The Game renderer runs the selected world's main loop (`runGame`).
    var paused = false {
        didSet { showLive() }
    }
    /// Play: the keyboard goes to the game and the view follows the player.
    var playing = false {
        didSet {
            if playing { paused = false }
            showLive()
        }
    }
    /// Counts restarts: the main loop starts again from the world's start-up state.
    private(set) var restarts = 0
    /// What the running loop shows of the selected room.
    private(set) var liveFrame: (world: World.ID, room: Int, image: CGImage)? {
        didSet {
            // A room keeps its last live frame as its thumbnail: the room as last seen.
            if let old = oldValue, old.world == selectedWorldID, old.room != liveFrame?.room {
                thumbnails[old.room] = old.image
            }
        }
    }
    /// Tick count and speed of the running loop.
    private(set) var loopStatus = ""

    /// Render caches; not observed, so filling them while a view draws is fine.
    @ObservationIgnored private var thumbnails: [Int: CGImage] = [:]
    @ObservationIgnored private var roomImage: (key: String, image: CGImage?)?
    /// Each world after its start-up code ran (nil: it could not run).
    @ObservationIgnored private var gameScreens: [World.ID: GameScreen?] = [:]
    @ObservationIgnored private var maps: [World.ID: WorldMap] = [:]
    @ObservationIgnored private var loop: (world: World.ID, loop: GameLoop)?
    /// Source of `liveFrame`: room, display mode, on screen or preview; and the page shown.
    @ObservationIgnored private var liveSource: (key: String, bytes: [UInt8])?
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
        maps = [:]
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
        if let live = liveImage(world: world, room: room) { return live }
        let key = "\(world.id)#\(room)#\(mode.rawValue)#\(renderer.rawValue)"
        if let cached = roomImage, cached.key == key { return cached.image }
        let image = HiresImage.make(screen(world: world, room: room), mode: mode)
        roomImage = (key, image)
        return image
    }

    /// The room as the running loop shows it, if it is the one on screen.
    func liveImage(world: World, room: Int) -> CGImage? {
        guard renderer == .game, let live = liveFrame, live.world == world.id, live.room == room else { return nil }
        return live.image
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

    /// The rooms laid out as they connect.
    func map(_ world: World) -> WorldMap {
        if let map = maps[world.id] { return map }
        let map = WorldMap(world: world)
        maps[world.id] = map
        return map
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
        return String(format: "The world's main loop on the 6502 emulator, its draw phase ($%04X–$%04X) drawing this room · native: %@",
                      game.phase.start, game.phase.end, natives)
    }

    // MARK: running the game

    /// Runs the world's main loop as in the game, paced by its CPU cycles at
    /// 1.0205 MHz, and shows the selected room.  Runs as the canvas's task:
    /// ends when the world, the renderer or `restarts` changes.
    func runGame(world: World) async {
        loop = nil
        liveFrame = nil
        liveSource = nil
        loopStatus = ""
        thumbnails = [:]                            // the rooms as the world starts
        guard renderer == .game, let game = gameScreen(world) else { return }
        let loop = game.loop(room: viewedRoom(world))
        self.loop = (world.id, loop)
        showLive()
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(15))
            // At most 0.1 s per step: a busy main thread slows the game down instead of skipping.
            let elapsed = min(clock.now - last, .milliseconds(100))
            last = clock.now
            guard !paused, loop.exit == nil else { continue }
            do {
                try loop.run(until: loop.cycles + UInt64(elapsed / .seconds(1) * GameLoop.clock))
            } catch {
                stopGame(error)
                return
            }
            showLive()
        }
    }

    /// Runs the paused main loop to the start of the next tick.
    func stepTick() {
        guard let running = loop, running.world == selectedWorldID else { return }
        do {
            // A tick is about 100,000 instructions; one that runs much longer waits for a key.
            try running.loop.runTick(maxSteps: 2_000_000)
            showLive()
        } catch CPU6502.CPUError.tooManySteps {
            showLive()
            loopStatus = "Paused in tick \(running.loop.ticks): the game waits for a key"
        } catch {
            stopGame(error)
        }
    }

    func restartGame() {
        restarts += 1
    }

    /// A key typed on the Apple's keyboard (Play): the game reads it at its next tick.
    func type(_ code: UInt8) {
        guard let running = loop, running.world == selectedWorldID else { return }
        running.loop.devices.type(code)
    }

    /// The room drawings stay (GameScreen); only the loop stops.
    private func stopGame(_ error: Error) {
        loop = nil
        liveFrame = nil
        loopStatus = "Main loop stopped: \(error)"
    }

    /// The room the loop draws: the selected one; when playing, and for code
    /// rooms (which can't be drawn elsewhere), the player's.
    private func viewedRoom(_ world: World) -> Int? {
        !playing && world.codeRooms[selectedRoom] == nil ? selectedRoom : nil
    }

    /// Updates `liveFrame` from the loop: the page on screen once the loop has
    /// drawn the selected room, until then the room drawn from the state at the
    /// start of the tick.  When playing, the selected room follows the room on screen.
    private func showLive() {
        guard let running = loop, let world = selectedWorld, world.id == running.world else { return }
        let loop = running.loop
        loop.room = viewedRoom(world)
        let speed = loop.tickCycles == 0 ? "" : String(format: " · %.1f ticks/s", GameLoop.clock / Double(loop.tickCycles))
        var status = paused ? "Paused at tick \(loop.ticks)" : "Tick \(loop.ticks)" + speed
        if let exit = loop.exit {
            status = "Tick \(loop.ticks): the world hands back to the loader, \(exit) – not emulated yet, Restart to play again"
        }
        if loopStatus != status { loopStatus = status }
        if playing, let shown = loop.shownRoom, shown != selectedRoom {
            selectedRoom = shown                    // shows it
            return
        }
        let room = selectedRoom
        guard playing || loop.room == room else {
            liveFrame = nil
            return
        }
        let shown = loop.shownRoom == room
        let key = "\(room)#\(mode.rawValue)#\(shown)"
        let screen: HiresScreen
        if shown {
            screen = loop.screen()
            if liveSource?.key == key, liveSource?.bytes == screen.bytes { return }
        } else {
            if liveSource?.key == key { return }
            do {
                screen = try loop.preview(room: room)
            } catch {
                renderErrors["\(world.id)#\(room)"] = error.localizedDescription
                liveFrame = nil
                return
            }
        }
        liveSource = (key, screen.bytes)
        if let image = HiresImage.make(screen, mode: mode) {
            liveFrame = (world.id, room, image)
        }
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
