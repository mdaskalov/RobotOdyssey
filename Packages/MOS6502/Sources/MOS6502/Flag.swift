extension CPU6502 {
    /// The bits of the status register `p`.
    public enum Flag {
        public static let carry: UInt8 = 0x01
        public static let zero: UInt8 = 0x02
        /// IRQs are ignored while it is set.
        public static let interrupt: UInt8 = 0x04
        /// ADC and SBC count in BCD.
        public static let decimal: UInt8 = 0x08
        /// Not a flag: set in the status PHP and BRK push, clear in the one IRQ
        /// and NMI push.
        public static let brk: UInt8 = 0x10
        /// Always reads 1.
        public static let unused: UInt8 = 0x20
        public static let overflow: UInt8 = 0x40
        public static let negative: UInt8 = 0x80
    }

    /// Sets N and Z by `value`; returns it.
    @discardableResult
    func nz(_ value: UInt8) -> UInt8 {
        p = p & ~(Flag.negative | Flag.zero) | value & Flag.negative | (value == 0 ? Flag.zero : 0)
        return value
    }

    func set(_ flag: UInt8, _ on: Bool) {
        p = on ? p | flag : p & ~flag
    }

    func isSet(_ flag: UInt8) -> Bool {
        p & flag != 0
    }

    /// The carry as a number, 0 or 1.
    var carry: UInt8 { p & Flag.carry }

    /// What PLP and RTI make of the status they pull: B clear, bit 5 set.
    func pullStatus() -> UInt8 {
        pull() & ~Flag.brk | Flag.unused
    }
}
