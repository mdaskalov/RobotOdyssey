import Foundation

/// Native port of the engine's robot drawing, called every tick right after the
/// room's objects: the outside of every robot in the current room ($D2BC in the
/// levels) and the inside of the robot whose interior is the current room
/// ($D72B).  Exact: memory is left byte for byte as the 6502 code leaves it,
/// including the animation counters and the random number generator at
/// $4E/$4F (Data/native_check.swift runs both and compares).  Registers are not
/// reproduced; the main loops only call other routines after these.
///
/// The three engine builds (Robotropolis levels; Robot Anatomy and Toolkit;
/// Innovation Lab and its tutorial) run the same code with the variables,
/// tables and sprites elsewhere, so the code is shared and each build has a
/// `Layout`.  See Docs/Robots.md.
struct RobotDrawing {
    /// Where one engine build keeps the robot code, variables, tables and sprites.
    struct Layout {
        let name: String
        /// Entry points: robot exteriors, robot interior.
        let exterior, interior: UInt16
        /// MD5 of the code from `exterior` to the end of the interior routine,
        /// per version; the native routines replace only code that matches.
        let fingerprints: [(code: Range<Int>, md5: String)]
        /// 4 robots in the levels; the other worlds have no robot 3.
        let robots: Int
        /// The levels reset the rainbow step before every draw, the others don't.
        let resetsRainbowStep: Bool

        // Robot state: 4 grabber bytes per robot, and $1A bytes per robot with
        // thrusters at +$0C, bumper colours at +$10, battery at +$18, switch at +$19.
        let grabbers, robotState: Int
        // Variables of the drawing code.
        let x, y, thrusters, bumpers, grabberCopy, antennaColour, antennaSignal, switchCopy: Int
        let scanPosition, sparkToggle, modulus, loop: Int
        let rainbowColour, rainbowStep, rainbowX, rainbowBit, rainbowRow, rainbowBits: Int
        let pulsePhase, pulseIndex: Int
        let battery, batteryRows, partIndex: Int
        // Tables.
        let grabberDX, grabberDY, scanDX, sparkDX, sparkDY, pulseStart, pulseColours: Int
        /// Flame sprite pointer tables (lo, hi) for thruster values 1, 2 and 3+.
        let thrusterSprites: [(lo: Int, hi: Int)]
        let thrusterDX, thrusterDY: Int
        /// The 10 parts drawn inside a robot: sprite pointer lo/hi, x, y.
        let partLo, partHi, partX, partY: Int
        // Sprites.
        let dot, blank, sparkA, sparkB, window, antenna, signal: Int
        let squares: [Int]
        /// Grabber sprites for the values 1, 2, 3 and anything else.
        let grabberSprites: [Int]
    }

    // Fixed in the code of every build.
    static let bodies = [0xF0, 0xF2, 0xF4, 0x01]
    static let antennaObjects = [0x66, 0xE6, 0xE3, 0x0C]      // the antenna takes this object's colour
    static let signalObjects = [0x59, 0xE5, 0xE2, 0x0B]       // orange = transmitting
    static let interiorRooms: [UInt8] = [0x09, 0x0A, 0x0B, 0x0D]
    static let interiorColours: [UInt8] = [7, 6, 7, 7]
    static let batteryFrame = 0x6C00, batteryCells = 0x6BE0, switchOn = 0x6D00, switchOff = 0x6D10

    static let levels = Layout(
        name: "levels", exterior: 0xD2BC, interior: 0xD72B,
        fingerprints: [(0xD2BC ..< 0xD832, "4a5515f1d2aee558379e2599f5cf6b3e"),     // v1.1
                       (0xD2BC ..< 0xD834, "4c776383e3538ddc873c2949379239ba")],    // v1.0
        robots: 4, resetsRainbowStep: true,
        grabbers: 0x8DBD, robotState: 0x8DCD,
        x: 0x8EBF, y: 0x8EC0, thrusters: 0x8EB6, bumpers: 0x8EB2, grabberCopy: 0x8E7E,
        antennaColour: 0x8E97, antennaSignal: 0x8E96, switchCopy: 0x8EBE,
        scanPosition: 0x8E98, sparkToggle: 0x8E99, modulus: 0x8EA1, loop: 0x8EA2,
        rainbowColour: 0x8E9A, rainbowStep: 0x8E9B, rainbowX: 0x8E9C, rainbowBit: 0x8E9D,
        rainbowRow: 0x8E9F, rainbowBits: 0x8EA0, pulsePhase: 0x8E9E, pulseIndex: 0x8ED6,
        battery: 0x8ED4, batteryRows: 0x8EC4, partIndex: 0x8E82,
        grabberDX: 0x82D7, grabberDY: 0x82DB, scanDX: 0x831B, sparkDX: 0x8329, sparkDY: 0x832C,
        pulseStart: 0x8331, pulseColours: 0x8334,
        thrusterSprites: [(0x836D, 0x8371), (0x8375, 0x8379), (0x837D, 0x8381)],
        thrusterDX: 0x8385, thrusterDY: 0x8389,
        partLo: 0x833D, partHi: 0x8347, partX: 0x8351, partY: 0x835B,
        dot: 0x84C4, blank: 0x84D4, sparkA: 0x8514, sparkB: 0x8524, window: 0x8534,
        antenna: 0x8544, signal: 0x8554, squares: [0x84E4, 0x84F4, 0x8504],
        grabberSprites: [0x6DC0, 0x6DD0, 0x6DE0, 0x6DB0])

    static let kit = Layout(
        name: "Robot Anatomy/Toolkit", exterior: 0xD2AB, interior: 0xD674,
        fingerprints: [(0xD2AB ..< 0xD768, "d50e2bc129cdc732a19152a78af33e34")],    // v1.0 = v1.1
        robots: 3, resetsRainbowStep: false,
        grabbers: 0x1ADF, robotState: 0x1AEB,
        x: 0x1BCF, y: 0x1BD0, thrusters: 0x1BC6, bumpers: 0x1BC2, grabberCopy: 0x1B97,
        antennaColour: 0x1BA8, antennaSignal: 0x1BA7, switchCopy: 0x1BCE,
        scanPosition: 0x1BA9, sparkToggle: 0x1BAA, modulus: 0x1BB1, loop: 0x1BB2,
        rainbowColour: 0x1BAB, rainbowStep: 0x1BAC, rainbowX: 0x1BAD, rainbowBit: 0x1BAE,
        rainbowRow: 0x1BAF, rainbowBits: 0x1BB0, pulsePhase: 0, pulseIndex: 0,
        battery: 0x1BE5, batteryRows: 0x1BD5, partIndex: 0x1BE7,
        grabberDX: 0x1CC4, grabberDY: 0x1CC8, scanDX: 0x1D04, sparkDX: 0x1D12, sparkDY: 0x1D15,
        pulseStart: 0, pulseColours: 0,
        thrusterSprites: [(0x1D4A, 0x1D4E), (0x1D52, 0x1D56), (0x1D5A, 0x1D5E)],
        thrusterDX: 0x1D62, thrusterDY: 0x1D66,
        partLo: 0x1D1A, partHi: 0x1D24, partX: 0x1D2E, partY: 0x1D38,
        dot: 0x1E98, blank: 0x1EA8, sparkA: 0x1EB8, sparkB: 0x1EC8, window: 0x1ED8,
        antenna: 0x1EE8, signal: 0x1EF8, squares: [],
        grabberSprites: [0x6DB0, 0x6DD0, 0x6DC0, 0x6DA0])

    static let lab = Layout(
        name: "Innovation Lab", exterior: 0xD2AB, interior: 0xD674,
        fingerprints: [(0xD2AB ..< 0xD768, "9616658087d8289557cccbafbc785647")],    // v1.0 = v1.1
        robots: 3, resetsRainbowStep: false,
        grabbers: 0x129F, robotState: 0x12AB,
        x: 0x1390, y: 0x1391, thrusters: 0x1387, bumpers: 0x1383, grabberCopy: 0x1358,
        antennaColour: 0x1369, antennaSignal: 0x1368, switchCopy: 0x138F,
        scanPosition: 0x136A, sparkToggle: 0x136B, modulus: 0x1372, loop: 0x1373,
        rainbowColour: 0x136C, rainbowStep: 0x136D, rainbowX: 0x136E, rainbowBit: 0x136F,
        rainbowRow: 0x1370, rainbowBits: 0x1371, pulsePhase: 0, pulseIndex: 0,
        battery: 0x13A6, batteryRows: 0x1396, partIndex: 0x13A8,
        grabberDX: 0x14A0, grabberDY: 0x14A4, scanDX: 0x14E4, sparkDX: 0x14F2, sparkDY: 0x14F5,
        pulseStart: 0, pulseColours: 0,
        thrusterSprites: [(0x152A, 0x152E), (0x1532, 0x1536), (0x153A, 0x153E)],
        thrusterDX: 0x1542, thrusterDY: 0x1546,
        partLo: 0x14FA, partHi: 0x1504, partX: 0x150E, partY: 0x1518,
        dot: 0x6A40, blank: 0x6A50, sparkA: 0x6CC0, sparkB: 0x6CD0, window: 0x6C90,
        antenna: 0x6CE0, signal: 0x6CF0, squares: [],
        grabberSprites: [0x6DB0, 0x6DD0, 0x6DC0, 0x6DA0])

    static let layouts = [levels, kit, lab]

    /// The layout whose code is in memory (language card bank 2 mapped), if any.
    static func layout(in mem: [UInt8]) -> Layout? {
        layouts.first { l in
            l.fingerprints.contains { DiskImage.md5(mem[$0.code]) == $0.md5 }
        }
    }

    let layout: Layout

    // MARK: outside ($D2BC)

    /// Robots 0, 1, 2 (and 3), each only if its body is in the current room.
    func drawExteriors(_ m: inout RAM) {
        drawRainbowRobot(&m)
        drawSparkingRobot(&m)
        drawScanningRobot(&m)
        if layout.robots == 4 { drawPulsingRobot(&m) }
    }

    private func inRoom(_ m: RAM, _ robot: Int) -> Bool {
        m[0x6300 + RobotDrawing.bodies[robot]] == m[RAM.currentRoom]
    }

    /// Robot 0 ($D44D): two blanks for its window, which is then drawn pixel by pixel in cycling colours.
    private func drawRainbowRobot(_ m: inout RAM) {
        guard inRoom(m, 0) else { return }
        let l = layout, body = RobotDrawing.bodies[0]
        m[l.x] = m[0x6400 + body]
        m.x = m[l.x] &+ 1
        m[l.y] = m[0x6500 + body]
        m.y = m[l.y] &+ 3
        m.sprite = l.blank
        m.drawSprite(colour: 4)
        m.x = m[l.x] &+ 5
        m.y = m[l.y] &+ 3
        m.drawSprite(colour: 4)
        if l.resetsRainbowStep { m[l.rainbowStep] = 0 }
        drawRainbow(&m, x: m[l.x] &+ 2, y: m[l.y])
        drawParts(&m, robot: 0)
    }

    /// Robot 1 ($D359): a blank, a spark pattern that alternates every tick and
    /// two dots at random places (the random number generator advances 32 steps).
    private func drawSparkingRobot(_ m: inout RAM) {
        guard inRoom(m, 1) else { return }
        let l = layout, body = RobotDrawing.bodies[1]
        m[l.x] = m[0x6400 + body]
        m[l.y] = m[0x6500 + body]
        m.x = m[l.x] &+ 3
        m.y = m[l.y] &+ 3
        m.sprite = l.blank
        m.drawSprite(colour: 4)
        if m[l.sparkToggle] != 0 {
            m[l.sparkToggle] = 0
            m.sprite = l.sparkA
        } else {
            m[l.sparkToggle] = 1
            m.sprite = l.sparkB
        }
        m.drawSprite(colour: 7)
        m.sprite = l.dot
        placeSpark(&m)
        m.drawSprite(colour: 6)
        placeSpark(&m)
        m.drawSprite(colour: 5)
        drawParts(&m, robot: 1)
    }

    /// Robot 2 ($D2C8): a black bar with a light running back and forth (14 positions).
    private func drawScanningRobot(_ m: inout RAM) {
        guard inRoom(m, 2) else { return }
        let l = layout, body = RobotDrawing.bodies[2]
        var add = Adder()
        m[l.x] = m[0x6400 + body]
        m[RAM.lineX1] = add(m[l.x], 1)
        m[RAM.lineX2] = add(m[RAM.lineX1], 9)
        add = Adder()
        m[l.y] = m[0x6500 + body]
        m[RAM.lineY1] = add(m[l.y], 7)
        m[RAM.lineY2] = add(m[RAM.lineY1], 1)
        m[RAM.lineColour] = 4
        m.drawBox()
        m.sprite = l.dot
        m.x = m[l.scanDX + Int(m[l.scanPosition])] &+ m[l.x]
        m.y = m[l.y] &+ 7
        m.drawSprite(colour: 5)
        m[l.scanPosition] &-= 1
        if m[l.scanPosition] & 0x80 != 0 { m[l.scanPosition] = 0x0D }
        drawParts(&m, robot: 2)
    }

    /// Robot 3 ($D4CC, levels only): three nested squares, the orange one moving inwards.
    private func drawPulsingRobot(_ m: inout RAM) {
        guard inRoom(m, 3) else { return }
        let l = layout, body = RobotDrawing.bodies[3]
        m[l.x] = m[0x6400 + body]
        m.x = m[l.x] &+ 3
        m[l.y] = m[0x6500 + body]
        m.y = m[l.y] &+ 3
        m.sprite = l.blank
        m.drawSprite(colour: 4)
        m[l.pulsePhase] &+= 1
        if m[l.pulsePhase] >= 3 { m[l.pulsePhase] = 0 }
        m.x &-= 1
        m[l.pulseIndex] = m[l.pulseStart + Int(m[l.pulsePhase])]
        for (k, square) in l.squares.enumerated() {
            if k > 0 { m[l.pulseIndex] &+= 1 }
            m.sprite = square
            m.drawSprite(colour: m[l.pulseColours + Int(m[l.pulseIndex])])
        }
        drawParts(&m, robot: 3)
    }

    /// What every robot has ($D573): bumpers (lines in the bumpers' colours),
    /// thruster flames, grabbers, the antenna and its signal.
    private func drawParts(_ m: inout RAM, robot i: Int) {
        let l = layout
        let state = l.robotState + 0x1A * i
        for k in (0 ..< 4).reversed() {
            m[l.thrusters + k] = m[state + 0x0C + k]
            m[l.bumpers + k] = m[state + 0x10 + k]
            m[l.grabberCopy + k] = m[l.grabbers + 4 * i + k]
        }
        m[l.antennaColour] = m[0x6200 + RobotDrawing.antennaObjects[i]]
        m[l.antennaSignal] = m[state + 0x18] != 0 && m[0x6200 + RobotDrawing.signalObjects[i]] == 5 ? 1 : 0

        var add = Adder()                                   // bottom, top, left, right bumper
        m[RAM.lineX1] = add(m[l.x], 3)
        m[RAM.lineX2] = add(m[RAM.lineX1], 5)
        m.y = m[l.y] &- 2
        m[RAM.lineColour] = m[l.bumpers]
        m.horizontalLine()
        m[RAM.lineColour] = m[l.bumpers + 2]
        m.y = m[l.y] &+ 0x12
        m.horizontalLine()
        m[RAM.lineColour] = m[l.bumpers + 1]
        add = Adder()
        m[RAM.lineY1] = add(m[l.y], 3)
        m[RAM.lineY2] = add(m[RAM.lineY1], 9)
        m.x = m[l.x] &- 2
        m.verticalLine()
        m[RAM.lineColour] = m[l.bumpers + 3]
        m.x = m[l.x] &+ 0x0D
        m.verticalLine()

        m[l.loop] = 3                                       // thrusters: up, right, down, left
        repeat {
            let k = Int(m[l.loop]), v = m[l.thrusters + k]
            if v != 0 {
                let table = l.thrusterSprites[min(Int(v), 3) - 1]
                m[RAM.spritePointer] = m[table.lo + k]
                m[RAM.spritePointer + 1] = m[table.hi + k]
                m.x = m[l.x] &+ m[l.thrusterDX + k]
                m.y = m[l.y] &+ m[l.thrusterDY + k]
                m.drawSprite(colour: 5)
            }
            m[l.loop] &-= 1
        } while m[l.loop] & 0x80 == 0

        m[l.loop] = 3                                       // grabbers
        repeat {
            let k = Int(m[l.loop]), v = m[l.grabberCopy + k]
            if v != 0 {
                m.sprite = l.grabberSprites[min(Int(v), 4) - 1]
                m.x = m[l.x] &+ m[l.grabberDX + k]
                m.y = m[l.y] &+ m[l.grabberDY + k]
                m.drawSprite(colour: 7)
            }
            m[l.loop] &-= 1
        } while m[l.loop] & 0x80 == 0

        m.sprite = l.antenna
        m.x = m[l.x]
        m.y = m[l.y] &+ 0x10
        m.drawSprite(colour: m[l.antennaColour])
        if m[l.antennaSignal] != 0 {
            m.sprite = l.signal
            m.drawSprite(colour: 7)
        }
    }

    /// $D6AB: the window sprite plotted pixel by pixel from (x, y), `step` units
    /// apart, each set pixel in the next of the colours 4-7 (the colour also
    /// advances once per bit).  Keeps the 6502's carry where it ends up in memory.
    private func drawRainbow(_ m: inout RAM, x: UInt8, y: UInt8) {
        let l = layout
        m.sprite = l.window
        var carry = m[l.rainbowStep] >= 1                   // CMP #$01
        if m[l.rainbowStep] != 1 { m[l.rainbowStep] &+= 1 }
        m[l.rainbowX] = x
        m.y = y
        m[l.rainbowRow] = 0
        repeat {
            m.x = m[l.rainbowX]
            m[l.rainbowBits] = m[(m.sprite + Int(m[l.rainbowRow])) & 0xFFFF]
            repeat {
                let bit = m[l.rainbowBits] & 0x80 != 0      // ROL
                m[l.rainbowBits] = m[l.rainbowBits] << 1 | (carry ? 1 : 0)
                if bit, m.y < 0xBE, m.x < 0x8B {
                    nextRainbowColour(&m)
                    m.plot(colour: m[l.rainbowColour])
                }
                m.x = m[l.rainbowStep] &+ m.x
                carry = nextRainbowColour(&m)
                m[l.rainbowBit] &-= 1
            } while m[l.rainbowBit] & 0x80 == 0
            m[l.rainbowBit] = 7
            m.y = m[l.rainbowStep] &+ m.y
            m[l.rainbowRow] &+= 1
            carry = false                                   // CPY #$10 below 16
        } while m[l.rainbowRow] < 0x10
    }

    /// Next colour 4, 5, 6, 7, 4...; true when it wrapped (the carry the code leaves).
    @discardableResult
    private func nextRainbowColour(_ m: inout RAM) -> Bool {
        m[layout.rainbowColour] &+= 1
        guard m[layout.rainbowColour] >= 8 else { return false }
        m[layout.rainbowColour] = 4
        return true
    }

    /// $D3F5: a random spark position on robot 1.
    private func placeSpark(_ m: inout RAM) {
        m.x = m[layout.sparkDX + Int(random(&m, below: 3))] &+ m[layout.x]
        m.y = m[layout.sparkDY + Int(random(&m, below: 5))] &+ m[layout.y]
    }

    /// $D414: a random number below n (n > 0), by subtraction.
    private func random(_ m: inout RAM, below n: UInt8) -> UInt8 {
        m[layout.modulus] = n
        var r = RobotDrawing.randomByte(&m)
        while r >= n { r -= n }
        return r
    }

    /// $D429: 8 steps of the 16-bit shift register at $4E/$4F; returns $4F.
    static func randomByte(_ m: inout RAM) -> UInt8 {
        for _ in 0 ..< 8 {
            let hi = m[0x4F]
            let feedback: UInt8 = (hi >> 5 ^ hi >> 6) & 1
            let carry = m[0x4E] >> 7
            m[0x4E] = m[0x4E] << 1 | feedback
            m[0x4F] = hi << 1 | carry
        }
        return m[0x4F]
    }

    // MARK: inside ($D72B)

    /// In a robot's interior room: the battery gauge, the robot's parts, the window and the switch.
    func drawInterior(_ m: inout RAM) {
        let rooms = RobotDrawing.interiorRooms.prefix(layout.robots)
        guard let i = rooms.firstIndex(of: m[RAM.currentRoom]) else { return }
        let l = layout, state = l.robotState + 0x1A * i
        m[l.switchCopy] = m[state + 0x19]
        drawBattery(&m, charge: m[state + 0x18])
        drawInside(&m, colour: RobotDrawing.interiorColours[i])
    }

    /// $D783: frame, cells and an orange bar of charge + 1 rows (none when empty).
    private func drawBattery(_ m: inout RAM, charge: UInt8) {
        let l = layout
        m[l.battery] = charge
        m.sprite = RobotDrawing.batteryFrame
        m.x = 0x15
        m.y = 0x21
        m.drawSprite(colour: 7)
        m.sprite = RobotDrawing.batteryCells
        m.x = 0x0E
        m.drawSprite(colour: 7)
        for k in 0 ..< 16 { m[l.batteryRows + k] = 0 }
        var row = m[l.battery]
        if row != 0 {
            repeat {
                m[l.batteryRows + Int(row)] = 0x0C
                row &-= 1
            } while row & 0x80 == 0
        }
        m.sprite = l.batteryRows
        m.drawSprite(colour: 5)
    }

    /// $D7D0: the 10 parts in the robot's colour, the window, and the switch (orange = on).
    private func drawInside(_ m: inout RAM, colour: UInt8) {
        let l = layout
        m[l.battery] = colour
        m[l.partIndex] = 9
        repeat {
            let k = Int(m[l.partIndex])
            m[RAM.spritePointer] = m[l.partLo + k]
            m[RAM.spritePointer + 1] = m[l.partHi + k]
            m.x = m[l.partX + k]
            m.y = m[l.partY + k]
            m.drawSprite(colour: m[l.battery])
            m[l.partIndex] &-= 1
        } while m[l.partIndex] & 0x80 == 0
        m.sprite = l.window
        m.x = 0x76
        m.y = 0x8E
        m.drawSprite(colour: 7)
        let on = m[l.switchCopy] != 0
        m.sprite = on ? RobotDrawing.switchOn : RobotDrawing.switchOff
        m.y = 0x21
        m.drawSprite(colour: on ? 5 : 7)
    }
}
