import Apple2Kit
import Foundation

/// What the three engines share by name, each at places of its own
/// (`LevelsSymbols`, `KitSymbols`, `LabSymbols`): the robots and the
/// circuits, the robot drawing, the soldering.  Code that runs in every
/// engine is written for these names – the natives for any map that has them
/// (`Engine`, the compiler makes a version an engine), the model and the
/// viewer for the map of the world they look at (`Variant.symbols`).  What
/// the names stand for is told where the levels declare them.
nonisolated protocol EngineSymbols: GameSymbols {
    /// The engine, and the disks' version: only the language card's $D000
    /// bank moved between v1.0 and v1.1, some routines with it.
    var build: EngineBuild { get }
    var version: Version { get }

    var grabberDX: Table { get }
    var grabberDY: Table { get }
    var scanDX: Table { get }
    var sparkDX: Table { get }
    var sparkDY: Table { get }
    var partSpritesLow: Table { get }
    var partSpritesHigh: Table { get }
    var partX: Table { get }
    var partY: Table { get }
    var flameSprites: Table { get }
    var flameDX: Table { get }
    var flameDY: Table { get }
    var dotSprite: Sprite { get }
    var blankSprite: Sprite { get }
    var sparkSprites: Sprite { get }
    var windowSprite: Sprite { get }
    var antennaSprite: Sprite { get }
    var signalSprite: Sprite { get }
    var wireTo: Table { get }
    var wireAX: Table { get }
    var wireBX: Table { get }
    var wireAY: Table { get }
    var wireBY: Table { get }
    var pinTypes: Table { get }
    var pinDX: Table { get }
    var pinDY: Table { get }
    var toolMode: Byte { get }
    var robotGrabbers: Table { get }
    var robotState: Table { get }
    var robotThrusters: Table { get }
    var robotBumpers: Table { get }
    var robotBattery: Table { get }
    var robotSwitch: Table { get }
    var grabState: Byte { get }
    var solderPin: Byte { get }
    var solderPinType: Byte { get }
    var solderX: Byte { get }
    var solderY: Byte { get }
    var solderRoom: Byte { get }
    var drawnGrabbers: Table { get }
    var partIndex: Byte { get }
    var keptDX: Byte { get }
    var keptDY: Byte { get }
    var antennaSignal: Byte { get }
    var antennaColour: Byte { get }
    var scanPosition: Byte { get }
    var sparkToggle: Byte { get }
    var rainbowColour: Byte { get }
    var rainbowStep: Byte { get }
    var rainbowX: Byte { get }
    var rainbowBit: Byte { get }
    var rainbowRow: Byte { get }
    var rainbowBits: Byte { get }
    var randomModulus: Byte { get }
    var partsLoop: Byte { get }
    var drawnBumpers: Table { get }
    var drawnThrusters: Table { get }
    var drawnSwitch: Byte { get }
    var robotX: Byte { get }
    var robotY: Byte { get }
    var batteryBar: Table { get }
    var drawnBattery: Byte { get }
    var carryWires: Routine { get }
    var carryRoom: Byte { get }
    var grabButton: Routine { get }
    var drawRobots: Routine { get }
    var drawRobot2Scan: Routine { get }
    var drawRobot1Sparks: Routine { get }
    var sparkPosition: Routine { get }
    var randomBelowA: Routine { get }
    var random: Routine { get }
    var randomStep: Routine { get }
    var drawRobot0Rainbow: Routine { get }
    var drawRobotParts: Routine { get }
    var drawRainbow: Routine { get }
    var drawRobotInterior: Routine { get }
    var drawBattery: Routine { get }
    var drawInteriorParts: Routine { get }
    var playerInRobot: Routine { get }
    var solderTouch: Routine { get }
    var unsolder: Routine { get }
    var solderWire: Routine { get }
    var tipOnPin: Routine { get }
    var drawSolderWire: Routine { get }
}
