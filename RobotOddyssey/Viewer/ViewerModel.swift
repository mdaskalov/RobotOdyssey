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
                selection = nil
                if let w = selectedWorld, !w.isRoomUsed(selectedRoom) {
                    selectedRoom = (0 ..< World.roomCount).first { w.isRoomUsed($0) } ?? 0
                }
            }
        }
    }
    var selectedRoom = 0 {
        didSet {
            if oldValue != selectedRoom {
                selection = nil
                showLive()
            }
        }
    }
    /// An object, another sprite drawn or a wire of the selected room (`contents`).
    var selection: RoomItem?
    var mode: HiresImage.Mode = .color {
        didSet {
            thumbnails = [:]
            showLive()
        }
    }
    var showEmptyRooms = false
    var showGrid = false
    var showInspector = true {
        didSet { showLive() }
    }
    /// The inspector's other sprites drawn are open: while the inspector is
    /// shown, the selected room's sprites are recorded (`updateContents`).
    var showSprites = UserDefaults.standard.bool(forKey: "showSprites") {
        didSet {
            UserDefaults.standard.set(showSprites, forKey: "showSprites")
            showLive()
        }
    }

    /// Pauses the selected world's main loop (`runGame`).
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
    /// The game's sounds on the Mac's speaker (the game's own Ctrl-S turns them off too).
    var sound = UserDefaults.standard.object(forKey: "sound") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(sound, forKey: "sound")
            if !sound { soundPlayer.stop() }
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
    /// The selected room as the loop last drew it (`updateContents`).
    private var liveContents: RoomContents?

    /// The selected world's rooms as it starts, for the thumbnails, and the
    /// maps: made off the main thread (`prepareRooms`), `roomsKey` says for what.
    private var startThumbnails: (key: String, images: [Int: CGImage])?
    private var maps: [World.ID: WorldMap] = [:]
    /// The rooms as last seen live, in place of `startThumbnails`.
    private var thumbnails: [Int: CGImage] = [:]
    /// Render caches; not observed, so filling them while a view draws is fine.
    @ObservationIgnored private var roomImage: (key: String, image: CGImage?)?
    /// Each world after its start-up code ran (nil: it could not run).
    @ObservationIgnored private var gameScreens: [World.ID: GameScreen?] = [:]
    @ObservationIgnored private var loop: (world: World.ID, loop: GameLoop)?
    @ObservationIgnored private let soundPlayer = SoundPlayer()
    /// The last sound the game played (GameSounds' name), for the status.
    @ObservationIgnored private var lastSound: String?
    /// Rooms the player left while playing, with the tick they left in: their
    /// last live frame shows the player at the exit (`redrawLeftRooms`).
    @ObservationIgnored private var leftRooms: [Int: Int] = [:]
    /// Source of `liveFrame`: room, display mode, on screen or preview; and the page shown.
    @ObservationIgnored private var liveSource: (key: String, bytes: [UInt8])?
    /// Source of `liveContents`: room and the draw on screen, or the preview.
    @ObservationIgnored private var contentsSource: String?
    @ObservationIgnored private var renderErrors: [String: String] = [:]

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
        load(urls)
        Bookmarks.save(urls)
    }

    func closeAll() {
        disks = []
        groups = []
        messages = []
        selectedWorldID = nil
        Bookmarks.clear()
    }

    /// At launch: the disk images in the app's resources (not tracked in git), then
    /// `urls` – by default the last opened disks.
    func openAtLaunch(_ urls: [URL] = Bookmarks.load()) {
        load([Bundle.main.resourceURL].compactMap { $0 } + urls)
    }

    /// Adds the disks in `urls` (files or folders), in order.  The first program
    /// disk side of a version wins: later ones of the same side and version are ignored.
    private func load(_ urls: [URL]) {
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
        var ignored: [String] = []
        for d in found where !disks.contains(where: { $0.md5 == d.md5 }) {
            let role = d.role
            if case .programSide = role, let first = disks.first(where: { $0.role == role }) {
                ignored.append("\(d.name) (\(first.name) loaded first)")
            } else {
                disks.append(d)
            }
        }
        if !ignored.isEmpty {
            problems.append("Ignored, same version and side: " + ignored.joined(separator: ", ") + ".")
        }
        rebuild(extraMessages: problems)
    }

    /// What the loader's code check found: an unknown version runs on the
    /// original code alone, and so do routines whose code isn't the version's.
    private func codeNotes(_ set: DiskSet, _ worlds: [World]) -> [String] {
        guard set.version != nil else {
            return ["\(set.title): version not recognized – the engine runs as original 6502 code only."]
        }
        return worlds.compactMap { w in
            guard let differing = w.codeCheck?.differing, !differing.isEmpty else { return nil }
            return "\(w.name) (v\(set.versionName)): " + differing.joined(separator: ", ")
                + " differ from the original code (modified disk?) – they run as 6502 code."
        }
    }

    private func diskFiles(at url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [url] }
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.filter { ["dsk", "do"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Pair the program disk sides of each version (`load` keeps one side A and
    /// one side B per version), build all worlds, then the saved games.
    private func rebuild(extraMessages: [String]) {
        var notes = extraMessages
        var sets: [String: DiskSet] = [:]
        var storage: [DiskImage] = []
        for d in disks {
            switch d.role {
            case .programSide(let side, let version):
                var set = sets[version?.rawValue ?? "1.x"] ?? DiskSet(version: version)
                if side == .a { set.sideA = d } else { set.sideB = d }
                sets[set.versionName] = set
            case .storage:
                storage.append(d)
            case .unknown:
                notes.append("\(d.name): not recognized (only Robot Odyssey I v1.0/v1.1 is supported so far).")
            }
        }
        var newGroups: [WorldGroup] = []
        let ordered = sets.sorted { $0.key > $1.key }
        for (key, set) in ordered {
            let (worlds, errors) = WorldBuilder(disks: set).buildAll(idPrefix: "\(key)/")
            notes += errors
            notes += codeNotes(set, worlds)
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
        startThumbnails = nil
        maps = [:]
        renderErrors = [:]
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
        if let live = liveImage(world: world, room: room) { return live }
        let key = "\(world.id)#\(room)#\(mode.rawValue)"
        if let cached = roomImage, cached.key == key { return cached.image }
        let image = HiresImage.make(screen(world: world, room: room), mode: mode)
        roomImage = (key, image)
        return image
    }

    /// The room as the running loop shows it, if it is the one on screen.
    func liveImage(world: World, room: Int) -> CGImage? {
        guard let live = liveFrame, live.world == world.id, live.room == room else { return nil }
        return live.image
    }

    /// The room as last seen, else as the world starts once `prepareRooms` has drawn it.
    func thumbnail(room: Int) -> CGImage? {
        thumbnails[room] ?? (thumbnailsReady ? startThumbnails?.images[room] : nil)
    }

    /// The selected room as the loop last drew it, else as the world starts.
    func contents(_ world: World) -> RoomContents {
        if let live = liveContents, live.world.id == world.id, live.room == selectedRoom { return live }
        return RoomContents(world: world, room: selectedRoom)
    }

    /// The room as the game draws it, else the static renderer (`Self.screen`).
    private func screen(world: World, room: Int) -> HiresScreen {
        let (screen, error) = Self.screen(world: world, room: room, game: gameScreen(world))
        if let error { renderErrors["\(world.id)#\(room)"] = error }
        return screen
    }

    /// The room as `game` draws it, else (code rooms, no main loop), or if
    /// its code fails (the error), as the static renderer does.
    private nonisolated static func screen(world: World, room: Int, game: GameScreen?) -> (HiresScreen, error: String?) {
        if world.codeRooms[room] == nil, let game {
            do {
                return (try game.render(room: room).screen, nil)
            } catch {
                return (RoomRenderer(world: world).render(room: room), error.localizedDescription)
            }
        }
        return (RoomRenderer(world: world).render(room: room), nil)
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

    /// The rooms laid out as they connect, once `prepareRooms` has done it.
    func map(_ world: World) -> WorldMap? {
        maps[world.id]
    }

    // MARK: preparing the rooms

    /// What the thumbnails as the world starts depend on.
    private var roomsKey: String? {
        selectedWorldID.map { "\($0)#\(mode.rawValue)" }
    }

    /// The thumbnails of the selected world as it starts are drawn.
    var thumbnailsReady: Bool {
        startThumbnails != nil && startThumbnails?.key == roomsKey
    }

    /// Draws the selected world's rooms as it starts, for the thumbnails, and
    /// lays out its map (`withMap`), off the main thread: the 6502 code draws
    /// each room, which takes seconds in a Debug build.  Runs as the rooms
    /// view's task, which shows progress until they are there.
    func prepareRooms(world: World, withMap: Bool) async {
        guard world.id == selectedWorldID, let key = roomsKey else { return }
        let draw = !thumbnailsReady, layOut = withMap && maps[world.id] == nil
        guard draw || layOut,
              let prepared = await Self.prepare(world, mode: mode, draw: draw, layOut: layOut),
              !Task.isCancelled else { return }
        renderErrors.merge(prepared.errors) { $1 }
        if let images = prepared.thumbnails { startThumbnails = (key, images) }
        if let map = prepared.map { maps[world.id] = map }
    }

    /// Every room's thumbnail but the code rooms', as `screen` draws it, and
    /// the map; nil when cancelled.
    @concurrent
    private nonisolated static func prepare(_ world: World, mode: HiresImage.Mode, draw: Bool, layOut: Bool) async
        -> (thumbnails: [Int: CGImage]?, map: WorldMap?, errors: [String: String])? {
        var errors: [String: String] = [:]
        var thumbnails: [Int: CGImage]?
        if draw {
            var gameScreen: GameScreen?
            do {
                gameScreen = try GameScreen(world: world)
            } catch {
                errors[world.id] = error.localizedDescription
            }
            var images: [Int: CGImage] = [:]
            for room in 0 ..< World.roomCount where world.codeRooms[room] == nil {
                guard !Task.isCancelled else { return nil }
                let (drawn, error) = screen(world: world, room: room, game: gameScreen)
                errors["\(world.id)#\(room)"] = error
                images[room] = HiresImage.make(drawn, mode: mode, scale: 1)
            }
            thumbnails = images
        }
        guard !Task.isCancelled else { return nil }
        return (thumbnails, layOut ? WorldMap(world: world) : nil, errors)
    }

    /// How the room in the canvas was drawn.
    func renderNote(world: World, room: Int) -> String {
        if world.codeRooms[room] != nil { return "Code room – drawn as walls by the static renderer" }
        if let e = renderErrors["\(world.id)#\(room)"] ?? renderErrors[world.id] {
            return "The game's code could not draw this room (\(e)) – static renderer"
        }
        guard let game = gameScreen(world) else { return "" }
        return String(format: "The world's main loop on the 6502 emulator; its draw phase ($%04X–$%04X) draws this room.",
                      game.phase.start, game.phase.end)
    }

    /// The native routines the game runs in place of the original code (`CodeCheck`).
    func natives(world: World) -> [(name: String, entry: UInt16)] {
        gameScreen(world)?.natives ?? []
    }

    // MARK: running the game

    /// Runs the world's main loop as in the game, paced by its CPU cycles at
    /// 1.0205 MHz, plays its sounds and shows the selected room.  Runs as the
    /// canvas's task: ends when the world or `restarts` changes.
    func runGame(world: World) async {
        loop = nil
        liveFrame = nil
        liveSource = nil
        liveContents = nil
        contentsSource = nil
        loopStatus = ""
        lastSound = nil
        soundPlayer.stop()
        thumbnails = [:]                            // the rooms as the world starts
        leftRooms = [:]
        guard let game = gameScreen(world) else { return }
        let loop = game.loop(room: viewedRoom(world))
        self.loop = (world.id, loop)
        showLive()
        let clock = ContinuousClock()
        var last = clock.now
        // The cycle the game should be at.  A sound takes its cycles at once
        // (the native PLAY_SOUNDS), and the loop waits here while it plays.
        var target: UInt64?
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(15))
            // At most 0.1 s per step: a busy main thread slows the game down instead of skipping.
            let elapsed = min(clock.now - last, .milliseconds(100))
            last = clock.now
            guard !paused, loop.exit == nil else {
                target = nil
                continue
            }
            let cycles = (target ?? loop.cycles) + UInt64(elapsed / .seconds(1) * GameLoop.clock)
            target = cycles
            do {
                try loop.run(until: cycles)
            } catch {
                stopGame(error)
                return
            }
            playSounds(loop)
            showLive()
        }
    }

    /// The sounds the loop played since the last call.
    private func playSounds(_ loop: GameLoop) {
        let sounds = loop.takeSounds()
        guard let latest = sounds.last else { return }
        lastSound = latest.name ?? latest.parameters.description
        if sound { soundPlayer.play(sounds) }
    }

    /// Runs the paused main loop to the start of the next tick.
    func stepTick() {
        guard let running = loop, running.world == selectedWorldID else { return }
        do {
            // A tick is about 100,000 instructions; one that runs much longer waits for a key.
            try running.loop.runTick(maxSteps: 2_000_000)
            playSounds(running.loop)
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
        if let lastSound { status += " · last sound \(lastSound)" }
        if let exit = loop.exit {
            status = "Tick \(loop.ticks): the world hands back to the loader, \(exit) – not emulated yet, Restart to play again"
        }
        if loopStatus != status { loopStatus = status }
        redrawLeftRooms(world, loop)
        if playing, let shown = loop.shownRoom, shown != selectedRoom {
            leftRooms[selectedRoom] = loop.ticks
            selectedRoom = shown                    // shows it
            return
        }
        let room = selectedRoom
        guard playing || loop.room == room else {
            liveFrame = nil
            return
        }
        let shown = loop.shownRoom == room
        updateContents(world, loop, room: room, shown: shown)
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

    /// Makes `liveContents` what `liveFrame` shows: the draw of the page on
    /// screen once the loop has drawn `room` (again with every new page),
    /// until then the preview.  Records the sprites only while the inspector
    /// shows them (`showSprites`): that draws the room once more as 6502 code
    /// (about 1 ms per tick in a Release build, 10 in a Debug one).
    private func updateContents(_ world: World, _ loop: GameLoop, room: Int, shown: Bool) {
        let record = showInspector && showSprites
        let source = (shown ? "\(room)#\(loop.flips)" : "\(room)#preview") + (record ? "#sprites" : "")
        guard source != contentsSource else { return }
        contentsSource = source
        let start = loop.memory(drawing: room)
        let live = world.with(mem: start.memory, bank1: start.bank1)
        // A draw that fails leaves the objects without their sprites.
        let sprites = record ? (try? loop.sprites(room: room)) : nil
        liveContents = RoomContents(world: live, room: room, live: true, sprites: sprites)
    }

    /// The thumbnails of the rooms the player left in an earlier tick, drawn
    /// from the state at the start of this one: the player is in the new room
    /// by then.  (At the room change, the start of the tick still has the
    /// player at the exit.)
    private func redrawLeftRooms(_ world: World, _ loop: GameLoop) {
        for (room, tick) in leftRooms where tick < loop.ticks {
            leftRooms[room] = nil
            guard room != selectedRoom, world.codeRooms[room] == nil,
                  let screen = try? loop.preview(room: room),
                  let image = HiresImage.make(screen, mode: mode, scale: 1) else { continue }
            thumbnails[room] = image
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
