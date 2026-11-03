# MOS6502

The NMOS 6502 of the Apple II and //e as AppleWin (and so Mariani) runs it, in
Swift: all 256 opcodes, the undocumented ones included, with their cycle
counts. Written for Robot Odyssey's hybrid engine, usable anywhere: add the
package by path or git and `import MOS6502`.

```swift
let cpu = CPU6502(memory: ram)              // 64K
cpu.ioPages[0xC0] = true                    // $C000-$C0FF go to ioRead/ioWrite
cpu.ioRead = { address in … }
cpu.ioWrite = { address, value in … }
cpu.pc = 0x0800
try cpu.step()                              // one instruction
try cpu.call(0x6000)                        // JSR and run until it returns
```

## Files

| File | What |
|---|---|
| `OpcodeTable.swift` | the 256 opcodes as `Opcode` values: byte, mnemonic, addressing mode, cycles, documented or not |
| `Opcode.swift` | `Opcode`: length, the page‑crossing rule, `Opcode(0xBD)` |
| `Mnemonic.swift` | what each instruction does, AppleWin's names for the undocumented ones, how it uses its operand (`Access`) |
| `AddressingMode.swift` | the 13 modes, their length and assembly syntax |
| `CPU6502.swift` | registers, memory and I/O pages, traps, `step`, `call`, reset, IRQ, NMI |
| `Addressing.swift` | finding the operand, and reading/writing it on the 6502's cycles |
| `Instructions.swift` | `execute`: every instruction, one line each where it can be |
| `UndocumentedInstructions.swift` | the undocumented ones that need more than a line |
| `Arithmetic.swift` | shifts, compare, ADC/SBC with the NMOS decimal mode |
| `Flag.swift` | the status bits |

## Cycles

`Opcode.cycles` is the count without extras; on top, as on the chip:

* +1 for an indexed read (abs,X, abs,Y, (zp),Y) whose index crosses a page.
  Writes and read‑modify‑writes always take that cycle, it is in their count
  (`Opcode.addsCycleOnPageCross` follows from `Mnemonic.access`).
* +1 for a branch taken, +1 more when it lands on another page than the
  next instruction's.

`cpu.cycles` counts on. Between instructions it is the cycle the next one
starts on. While an instruction runs, a read or write sees the cycle the
6502 makes it on: the instruction's last for reads and writes; a
read‑modify‑write (INC, ASL, …, DCP, ISC, …) reads three cycles before its
end and writes on its last. `LDA $C030` at cycle 1000 reads the speaker at
1003, `INC $C030` reads at 1003 and writes at 1005. (AppleWin hands its I/O
handlers the cycle the instruction starts on; the distances between accesses
of the same kind are the same.)

Each instruction makes the accesses its operation needs – one read, one write,
or a read then a write – and, as AppleWin, none of the 6502's dummy accesses
(the read at the unfixed address of an index crossing a page, the old value
written back by a read‑modify‑write).

## Undocumented opcodes

They run as on the chip; AppleWin names differ for several
(`Mnemonic.swift`): SLO (ASO), RLA, SRE (LSE), RRA, SAX (AXS), LAX, DCP (DCM),
ISC (INS), ANC, ALR, ARR, ANE (XAA), LXA (OAL), SBX (SAX), SHA (AXA), SHX
(XAS), SHY (SAY), TAS, LAS, the NOPs with operands (they read it) and JAM
(HLT). A JAM halts the CPU: `step` throws `CPUError.jammed` and PC stays on
it until `reset`. ANE and LXA mix in a constant that varies between chips;
these take AppleWin's ($FF and $EE).

## Where it differs from AppleWin

The results are the 6502's where AppleWin's differ from it:

| Opcodes | 6502 | AppleWin |
|---|---|---|
| DCP | DEC of $00 is $FF, compared with A = $FF: C set | keeps 16 bits, compares with $FFFF: C clear |
| ISC | INC of $FF is $00, subtracted: C set unless A − borrow < 0 | subtracts $100: C clear |
| ARR in decimal mode | the digit fixes are decided on the AND result | decided on the rotated value |
| NOP with an operand | reads it (a soft switch there switches) | doesn't |

BRK runs as on the chip (pushes, I, the vector at $FFFE) unless `stopsAtBRK`
is set: then `step` throws `CPUError.brk`, for hosts with no ROM behind the
vector. B is never set in `p`, only in the copy PHP and BRK push.

## Checks

* `swift test`: the table, cycles and bus cycles, decimal mode, the JMP
  ($xxFF) bug, BRK/RTI/IRQ, JAM, the undocumented edge cases.
* Against AppleWin's own code: Robot Odyssey's `Data/cpu_check.sh
  path/to/AppleWin [N]` builds AppleWin's `cpu6502.h` (from the checkout,
  with a small shim) and runs N random instructions of every opcode on both
  (random registers, flags, PC, operands, memory), comparing registers,
  flags, cycles, the jam and every byte written. 10,000 of each (2.56 M):
  identical but for the table above.
* The opcodes that differ, and the store/load ones with odd high‑byte
  behaviour (SHA, SHX, SHY, TAS, LAS, LXA), were run on Tom Harte's
  SingleStepTests (6502 v1, from real chip behaviour, 10,000 cases each):
  all identical, cycle counts included, but ANE, where those take $EE.
