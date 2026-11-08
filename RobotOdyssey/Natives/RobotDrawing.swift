import Foundation
import MOS6502

/// The robots in the engine's order (robot 0-3, the raw value), with what the
/// robot drawing has fixed in its instructions, in every engine (Docs/Robots.md).
/// The manual names the three of Robotropolis (Robot Anatomy: "Sparky,
/// Checkers, and Scanner"); the fourth, freed in Level 4, has no name in the
/// game and is named after its look here.
nonisolated enum Robot: Int, CaseIterable, CustomStringConvertible {
    /// Robot 0: its checkered window drawn in cycling colours.
    case checkers
    /// Robot 1: sparks and two dots at random places.
    case sparky
    /// Robot 2: a light running along a bar.
    case scanner
    /// Robot 3 (levels only): three nested squares pulsing inwards.
    case pulser

    var description: String {
        switch self {
        case .checkers: "Checkers"
        case .sparky: "Sparky"
        case .scanner: "Scanner"
        case .pulser: "Pulser"
        }
    }

    /// The robots of an engine: all 4 in the levels; the other worlds have no robot 3.
    static func all(_ engine: EngineBuild) -> ArraySlice<Robot> {
        allCases.prefix(engine == .levels ? 4 : 3)
    }

    /// Body object, interior room and the colour of its parts there; the
    /// antenna takes the colour of the antenna object and transmits when the
    /// signal object is orange.
    private var fixed: (body: UInt8, interiorRoom: UInt8, interiorColour: UInt8, antenna: UInt8, signal: UInt8) {
        switch self {
        case .checkers: (0xF0, 0x09, 7, 0x66, 0x59)
        case .sparky:   (0xF2, 0x0A, 6, 0xE6, 0xE5)
        case .scanner:  (0xF4, 0x0B, 7, 0xE3, 0xE2)
        case .pulser:   (0x01, 0x0D, 7, 0x0C, 0x0B)
        }
    }

    var body: UInt8 { fixed.body }
    var interiorRoom: UInt8 { fixed.interiorRoom }
    var interiorColour: UInt8 { fixed.interiorColour }
    var antennaObject: UInt8 { fixed.antenna }
    var signalObject: UInt8 { fixed.signal }

    /// Bytes of each robot's state (ROBOT_STATE and the tables in it).
    static let stateSize = 0x1A
    /// Where its state starts in ROBOT_STATE and the tables in it (thrusters, bumpers, battery, switch).
    var state: Int { Robot.stateSize * rawValue }
    /// Where its 4 grabbers start in ROBOT_GRABBERS.
    var grabbers: Int { 4 * rawValue }

    /// World sprites: the battery's frame and cells, the switch on and off.
    static let batteryFrame = 32, batteryCells = 30, switchOn = 48, switchOff = 49

    /// The world sprite of a grabber of value 1, 2, 3 and anything else (not 0: none).
    static func grabberSprite(_ value: UInt8, _ engine: EngineBuild) -> Int {
        (engine == .levels ? levelsGrabbers : otherGrabbers)[min(Int(value), 4) - 1]
    }
    private static let levelsGrabbers = [60, 61, 62, 59], otherGrabbers = [59, 61, 60, 58]
}

/// Native port of the engine's robot drawing, called every tick right after
/// the room's objects: the outside of every robot in the current room
/// (DRAW_ROBOTS) and the inside of the robot whose interior is the current
/// room (DRAW_ROBOT_INTERIOR).  Exact: memory is left byte for byte as the
/// 6502 code leaves it, including the animation counters and the random
/// number generator (Data/native_check.swift runs both and compares).
/// Registers are not reproduced; the main loops only call other routines
/// after these.
///
/// The three engines run the same code with the variables, tables and
/// sprites elsewhere (GameSymbols has them all); the levels' has a fourth
/// robot and resets the rainbow's step before every draw.  See Docs/Robots.md.
nonisolated extension Engine {
    // MARK: outside

    /// DRAW_ROBOTS ($D2BC in the levels): robots 0, 1, 2 (and 3), each only
    /// if its body is in the current room: its own look at the body's
    /// position (ROBOT_X/Y, both set before anything is drawn), then its parts.
    func drawRobots() {
        for robot in Robot.all(build) where m.objRoom[robot.body] == m.currentRoom {
            m.robotX = m.objX[robot.body]
            m.robotY = m.objY[robot.body]
            switch robot {
            case .checkers: drawCheckers()
            case .sparky: drawSparky()
            case .scanner: drawScanner()
            case .pulser: drawPulser()
            }
            drawParts(of: robot)
        }
    }

    /// DRAW_ROBOT0_RAINBOW: two blanks for its window, which is then drawn
    /// pixel by pixel in cycling colours.
    private func drawCheckers() {
        m.drawX = m.robotX &+ 1
        m.drawY = m.robotY &+ 3
        m.spritePointer = m.blankSprite
        drawSprite(colour: 4)
        m.drawX = m.robotX &+ 5
        m.drawY = m.robotY &+ 3
        drawSprite(colour: 4)
        if build == .levels { m.rainbowStep = 0 }
        drawRainbow(x: m.robotX &+ 2, y: m.robotY)
    }

    /// DRAW_ROBOT1_SPARKS: a blank, a spark pattern that alternates every tick
    /// and two dots at random places (the random number generator advances 32 steps).
    private func drawSparky() {
        m.drawX = m.robotX &+ 3
        m.drawY = m.robotY &+ 3
        m.spritePointer = m.blankSprite
        drawSprite(colour: 4)
        if m.sparkToggle != 0 {
            m.sparkToggle = 0
            m.spritePointer = m.sparkSprites
        } else {
            m.sparkToggle = 1
            m.spritePointer = m.sparkSprites + 16
        }
        drawSprite(colour: 7)
        m.spritePointer = m.dotSprite
        placeSpark()
        drawSprite(colour: 6)
        placeSpark()
        drawSprite(colour: 5)
    }

    /// DRAW_ROBOT2_SCAN: a black bar with a light running back and forth (14 positions).
    private func drawScanner() {
        var add = CPU6502.Adder()
        m.lineX1 = add(m.robotX, 1)
        m.lineX2 = add(m.lineX1, 9)
        add = CPU6502.Adder()
        m.lineY1 = add(m.robotY, 7)
        m.lineY2 = add(m.lineY1, 1)
        m.lineColour = 4
        drawBox()
        m.spritePointer = m.dotSprite
        m.drawX = m.scanDX[m.scanPosition] &+ m.robotX
        m.drawY = m.robotY &+ 7
        drawSprite(colour: 5)
        m.scanPosition &-= 1
        if m.scanPosition & 0x80 != 0 { m.scanPosition = 0x0D }
    }

    /// DRAW_ROBOT3_PULSE (levels only): three nested squares, the orange one moving inwards.
    private func drawPulser() {
        m.drawX = m.robotX &+ 3
        m.drawY = m.robotY &+ 3
        m.spritePointer = m.blankSprite
        drawSprite(colour: 4)
        m.pulsePhase &+= 1
        if m.pulsePhase >= 3 { m.pulsePhase = 0 }
        m.drawX &-= 1
        m.pulseIndex = m.pulseStart[m.pulsePhase]
        for square in 0 ..< 3 {
            if square > 0 { m.pulseIndex &+= 1 }
            m.spritePointer = m.squareSprites + 16 * square
            drawSprite(colour: m.pulseColours[m.pulseIndex])
        }
    }

    /// DRAW_ROBOT_PARTS: what every robot has: bumpers (lines in the bumpers'
    /// colours), thruster flames, grabbers, the antenna and its signal.
    private func drawParts(of robot: Robot) {
        for k in (0 ..< 4).reversed() {
            m.drawnThrusters[k] = m.robotThrusters[robot.state + k]
            m.drawnBumpers[k] = m.robotBumpers[robot.state + k]
            m.drawnGrabbers[k] = m.robotGrabbers[robot.grabbers + k]
        }
        m.antennaColour = m.objColour[robot.antennaObject]
        m.antennaSignal = m.robotBattery[robot.state] != 0 && m.objColour[robot.signalObject] == 5 ? 1 : 0

        var add = CPU6502.Adder()                           // bottom, top, left, right bumper
        m.lineX1 = add(m.robotX, 3)
        m.lineX2 = add(m.lineX1, 5)
        m.drawY = m.robotY &- 2
        m.lineColour = m.drawnBumpers[0]
        horizontalLine()
        m.lineColour = m.drawnBumpers[2]
        m.drawY = m.robotY &+ 0x12
        horizontalLine()
        m.lineColour = m.drawnBumpers[1]
        add = CPU6502.Adder()
        m.lineY1 = add(m.robotY, 3)
        m.lineY2 = add(m.lineY1, 9)
        m.drawX = m.robotX &- 2
        verticalLine()
        m.lineColour = m.drawnBumpers[3]
        m.drawX = m.robotX &+ 0x0D
        verticalLine()

        m.partsLoop = 3                                     // thrusters: up, right, down, left
        repeat {
            let k = Int(m.partsLoop), value = m.drawnThrusters[k]
            if value != 0 {
                let flames = 8 * (min(Int(value), 3) - 1)
                m.spritePointer = Int(m.flameSprites[flames + k]) | Int(m.flameSprites[flames + 4 + k]) << 8
                m.drawX = m.robotX &+ m.flameDX[k]
                m.drawY = m.robotY &+ m.flameDY[k]
                drawSprite(colour: 5)
            }
            m.partsLoop &-= 1
        } while m.partsLoop & 0x80 == 0

        m.partsLoop = 3                                     // grabbers
        repeat {
            let k = Int(m.partsLoop), value = m.drawnGrabbers[k]
            if value != 0 {
                m.spritePointer = sprite(Robot.grabberSprite(value, build))
                m.drawX = m.robotX &+ m.grabberDX[k]
                m.drawY = m.robotY &+ m.grabberDY[k]
                drawSprite(colour: 7)
            }
            m.partsLoop &-= 1
        } while m.partsLoop & 0x80 == 0

        m.spritePointer = m.antennaSprite
        m.drawX = m.robotX
        m.drawY = m.robotY &+ 0x10
        drawSprite(colour: m.antennaColour)
        if m.antennaSignal != 0 {
            m.spritePointer = m.signalSprite
            drawSprite(colour: 7)
        }
    }

    /// DRAW_RAINBOW: the window sprite plotted pixel by pixel from (x, y),
    /// RAINBOW_STEP units apart, each set pixel in the next of the colours 4-7
    /// (the colour also advances once per bit).  Keeps the 6502's carry where
    /// it ends up in memory.
    private func drawRainbow(x: UInt8, y: UInt8) {
        m.spritePointer = m.windowSprite
        var carry = m.rainbowStep >= 1                      // CMP #$01
        if m.rainbowStep != 1 { m.rainbowStep &+= 1 }
        m.rainbowX = x
        m.drawY = y
        m.rainbowRow = 0
        repeat {
            m.drawX = m.rainbowX
            m.rainbowBits = m[m.spritePointer + Int(m.rainbowRow)]
            repeat {
                let bit = m.rainbowBits & 0x80 != 0         // ROL
                m.rainbowBits = m.rainbowBits << 1 | (carry ? 1 : 0)
                if bit, m.drawY < 0xBE, m.drawX < 0x8B {
                    nextRainbowColour()
                    plot(colour: m.rainbowColour)
                }
                m.drawX = m.rainbowStep &+ m.drawX
                carry = nextRainbowColour()
                m.rainbowBit &-= 1
            } while m.rainbowBit & 0x80 == 0
            m.rainbowBit = 7
            m.drawY = m.rainbowStep &+ m.drawY
            m.rainbowRow &+= 1
            carry = false                                   // CPY #$10 below 16
        } while m.rainbowRow < 0x10
    }

    /// Next colour 4, 5, 6, 7, 4...; true when it wrapped (the carry the code leaves).
    @discardableResult
    private func nextRainbowColour() -> Bool {
        m.rainbowColour &+= 1
        guard m.rainbowColour >= 8 else { return false }
        m.rainbowColour = 4
        return true
    }

    /// SPARK_POSITION: a random spark position on robot 1.
    private func placeSpark() {
        m.drawX = m.sparkDX[random(below: 3)] &+ m.robotX
        m.drawY = m.sparkDY[random(below: 5)] &+ m.robotY
    }

    /// RANDOM_BELOW_A: a random number below n (n > 0), by subtraction.
    private func random(below n: UInt8) -> UInt8 {
        m.randomModulus = n
        var value = randomByte()
        while value >= n { value -= n }
        return value
    }

    /// RANDOM: 8 steps of the 16-bit shift register RANDOM_LOW/HIGH; returns the high byte.
    private func randomByte() -> UInt8 {
        for _ in 0 ..< 8 {
            let high = m.randomHigh
            let feedback: UInt8 = (high >> 5 ^ high >> 6) & 1
            let carry = m.randomLow >> 7
            m.randomLow = m.randomLow << 1 | feedback
            m.randomHigh = high << 1 | carry
        }
        return m.randomHigh
    }

    // MARK: inside

    /// DRAW_ROBOT_INTERIOR ($D72B in the levels): in a robot's interior room,
    /// the battery gauge, the robot's parts, the window and the switch.
    func drawRobotInterior() {
        guard let robot = Robot.all(build).first(where: { $0.interiorRoom == m.currentRoom }) else { return }
        m.drawnSwitch = m.robotSwitch[robot.state]
        drawBattery(charge: m.robotBattery[robot.state])
        drawInteriorParts(colour: robot.interiorColour)
    }

    /// DRAW_BATTERY: frame, cells and an orange bar of charge + 1 rows (none when empty).
    private func drawBattery(charge: UInt8) {
        m.drawnBattery = charge
        m.spritePointer = sprite(Robot.batteryFrame)
        m.drawX = 0x15
        m.drawY = 0x21
        drawSprite(colour: 7)
        m.spritePointer = sprite(Robot.batteryCells)
        m.drawX = 0x0E
        drawSprite(colour: 7)
        for row in 0 ..< 16 { m.batteryBar[row] = 0 }
        var row = m.drawnBattery
        if row != 0 {
            repeat {
                m.batteryBar[row] = 0x0C
                row &-= 1
            } while row & 0x80 == 0
        }
        m.spritePointer = m.batteryBar.address
        drawSprite(colour: 5)
    }

    /// DRAW_INTERIOR_PARTS: the 10 parts in the robot's colour, the window,
    /// and the switch (orange = on).
    private func drawInteriorParts(colour: UInt8) {
        m.drawnBattery = colour
        m.partIndex = 9
        repeat {
            let k = m.partIndex
            m.spritePointer = Int(m.partSpritesLow[k]) | Int(m.partSpritesHigh[k]) << 8
            m.drawX = m.partX[k]
            m.drawY = m.partY[k]
            drawSprite(colour: m.drawnBattery)
            m.partIndex &-= 1
        } while m.partIndex & 0x80 == 0
        m.spritePointer = m.windowSprite
        m.drawX = 0x76
        m.drawY = 0x8E
        drawSprite(colour: 7)
        let on = m.drawnSwitch != 0
        m.spritePointer = sprite(on ? Robot.switchOn : Robot.switchOff)
        m.drawY = 0x21
        drawSprite(colour: on ? 5 : 7)
    }
}
