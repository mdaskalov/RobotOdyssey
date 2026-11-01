import Foundation

/// What the robot drawing has fixed in its instructions, in every engine.
nonisolated enum Robot {
    /// The robots' body objects.
    static let bodies: [UInt8] = [0xF0, 0xF2, 0xF4, 0x01]
    /// The antenna takes the colour of the first object; the second orange means transmitting.
    static let antennaObjects: [UInt8] = [0x66, 0xE6, 0xE3, 0x0C]
    static let signalObjects: [UInt8] = [0x59, 0xE5, 0xE2, 0x0B]
    static let interiorRooms: [UInt8] = [0x09, 0x0A, 0x0B, 0x0D]
    static let interiorColours: [UInt8] = [7, 6, 7, 7]
    /// Bytes of each robot's state (ROBOT_STATE and the tables in it).
    static let stateSize = 0x1A
    /// World sprites: the battery's frame and cells, the switch on and off.
    static let batteryFrame = 32, batteryCells = 30, switchOn = 48, switchOff = 49

    /// 4 robots in the levels; the other worlds have no robot 3.
    static func count(_ engine: EngineBuild) -> Int { engine == .levels ? 4 : 3 }

    /// The world sprites of a grabber of value 1, 2, 3 and anything else.
    static func grabberSprites(_ engine: EngineBuild) -> [Int] {
        engine == .levels ? [60, 61, 62, 59] : [59, 61, 60, 58]
    }
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
    /// if its body is in the current room.
    func drawRobots() {
        drawRainbowRobot()
        drawSparkingRobot()
        drawScanningRobot()
        if build == .levels { drawPulsingRobot() }
    }

    private func inRoom(_ robot: Int) -> Bool {
        m.objRoom[Robot.bodies[robot]] == m.currentRoom
    }

    /// DRAW_ROBOT0_RAINBOW: two blanks for its window, which is then drawn
    /// pixel by pixel in cycling colours.
    private func drawRainbowRobot() {
        guard inRoom(0) else { return }
        let body = Robot.bodies[0]
        m.robotX = m.objX[body]
        m.drawX = m.robotX &+ 1
        m.robotY = m.objY[body]
        m.drawY = m.robotY &+ 3
        m.spritePointer = m.blankSprite
        drawSprite(colour: 4)
        m.drawX = m.robotX &+ 5
        m.drawY = m.robotY &+ 3
        drawSprite(colour: 4)
        if build == .levels { m.rainbowStep = 0 }
        drawRainbow(x: m.robotX &+ 2, y: m.robotY)
        drawParts(of: 0)
    }

    /// DRAW_ROBOT1_SPARKS: a blank, a spark pattern that alternates every tick
    /// and two dots at random places (the random number generator advances 32 steps).
    private func drawSparkingRobot() {
        guard inRoom(1) else { return }
        let body = Robot.bodies[1]
        m.robotX = m.objX[body]
        m.robotY = m.objY[body]
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
        drawParts(of: 1)
    }

    /// DRAW_ROBOT2_SCAN: a black bar with a light running back and forth (14 positions).
    private func drawScanningRobot() {
        guard inRoom(2) else { return }
        let body = Robot.bodies[2]
        var add = Adder()
        m.robotX = m.objX[body]
        m.lineX1 = add(m.robotX, 1)
        m.lineX2 = add(m.lineX1, 9)
        add = Adder()
        m.robotY = m.objY[body]
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
        drawParts(of: 2)
    }

    /// DRAW_ROBOT3_PULSE (levels only): three nested squares, the orange one moving inwards.
    private func drawPulsingRobot() {
        guard inRoom(3) else { return }
        let body = Robot.bodies[3]
        m.robotX = m.objX[body]
        m.drawX = m.robotX &+ 3
        m.robotY = m.objY[body]
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
        drawParts(of: 3)
    }

    /// DRAW_ROBOT_PARTS: what every robot has: bumpers (lines in the bumpers'
    /// colours), thruster flames, grabbers, the antenna and its signal.
    private func drawParts(of robot: Int) {
        let state = Robot.stateSize * robot
        for k in (0 ..< 4).reversed() {
            m.drawnThrusters[k] = m.robotThrusters[state + k]
            m.drawnBumpers[k] = m.robotBumpers[state + k]
            m.drawnGrabbers[k] = m.robotGrabbers[4 * robot + k]
        }
        m.antennaColour = m.objColour[Robot.antennaObjects[robot]]
        m.antennaSignal = m.robotBattery[state] != 0 && m.objColour[Robot.signalObjects[robot]] == 5 ? 1 : 0

        var add = Adder()                                   // bottom, top, left, right bumper
        m.lineX1 = add(m.robotX, 3)
        m.lineX2 = add(m.lineX1, 5)
        m.drawY = m.robotY &- 2
        m.lineColour = m.drawnBumpers[0]
        horizontalLine()
        m.lineColour = m.drawnBumpers[2]
        m.drawY = m.robotY &+ 0x12
        horizontalLine()
        m.lineColour = m.drawnBumpers[1]
        add = Adder()
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
                m.spritePointer = sprite(Robot.grabberSprites(build)[min(Int(value), 4) - 1])
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
        let rooms = Robot.interiorRooms.prefix(Robot.count(build))
        guard let i = rooms.firstIndex(of: m.currentRoom) else { return }
        let state = Robot.stateSize * i
        m.drawnSwitch = m.robotSwitch[state]
        drawBattery(charge: m.robotBattery[state])
        drawInteriorParts(colour: Robot.interiorColours[i])
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
