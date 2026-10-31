#!/usr/bin/env python3
"""Small NMOS 6502 emulator (documented opcodes) with cycle counting.

Memory is a flat 64K bytearray; reads/writes in $C000-$C0FF go to io_read /
io_write so callers can fake the keyboard, speaker, soft switches, etc.
Used to run original game code headless (e.g. level exit scripts) and to
measure how many CPU cycles a game tick takes.
"""

C, Z, I, D, B, U, V, N = 1, 2, 4, 8, 16, 32, 64, 128


class CPU:
    def __init__(self, mem):
        self.mem = mem
        self.a = self.x = self.y = 0
        self.sp = 0xFF
        self.p = U | I
        self.pc = 0
        self.cycles = 0
        self.io_read = lambda addr: 0
        self.io_write = lambda addr, v: None

    # --- memory ----------------------------------------------------------
    def rd(self, a):
        if 0xC000 <= a <= 0xC0FF:
            return self.io_read(a) & 0xFF
        return self.mem[a]

    def wr(self, a, v):
        if 0xC000 <= a <= 0xC0FF:
            self.io_write(a, v)
        else:
            self.mem[a] = v & 0xFF

    def rd16(self, a):
        return self.rd(a) | self.rd((a + 1) & 0xFFFF) << 8

    def push(self, v):
        self.mem[0x100 + self.sp] = v & 0xFF
        self.sp = (self.sp - 1) & 0xFF

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.mem[0x100 + self.sp]

    # --- flags -----------------------------------------------------------
    def nz(self, v):
        self.p = (self.p & ~(N | Z)) | (v & N) | (0 if v else Z)
        return v

    def flag(self, f, on):
        self.p = (self.p | f) if on else (self.p & ~f)

    # --- run -------------------------------------------------------------
    def call(self, addr, stop_at=(), max_steps=5_000_000):
        """JSR to addr; run until it returns or PC hits an address in stop_at."""
        self.push(0xFF)
        self.push(0xFE)                        # return to $FFFF -> sentinel
        self.pc = addr
        for _ in range(max_steps):
            if self.pc == 0xFFFF or self.pc in stop_at:
                return self.pc
            self.step()
        raise RuntimeError(f"no return after {max_steps} steps, pc=${self.pc:04X}")

    def step(self):
        op = self.rd(self.pc)
        handler = _OPS.get(op)
        if handler is None:
            raise RuntimeError(f"illegal opcode ${op:02X} at ${self.pc:04X}")
        fn, mode, cyc = handler
        self.pc = (self.pc + 1) & 0xFFFF
        addr, extra = _MODES[mode](self)
        self.cycles += cyc
        fn(self, addr, mode, extra)


# --- addressing modes: return (effective address, page-cross penalty) ------
def _imp(c): return None, 0
def _imm(c):
    a = c.pc; c.pc = (c.pc + 1) & 0xFFFF; return a, 0
def _zp(c):
    a = c.rd(c.pc); c.pc = (c.pc + 1) & 0xFFFF; return a, 0
def _zpx(c):
    a = (c.rd(c.pc) + c.x) & 0xFF; c.pc = (c.pc + 1) & 0xFFFF; return a, 0
def _zpy(c):
    a = (c.rd(c.pc) + c.y) & 0xFF; c.pc = (c.pc + 1) & 0xFFFF; return a, 0
def _abs(c):
    a = c.rd16(c.pc); c.pc = (c.pc + 2) & 0xFFFF; return a, 0
def _abx(c):
    b = c.rd16(c.pc); c.pc = (c.pc + 2) & 0xFFFF; a = (b + c.x) & 0xFFFF
    return a, int((a ^ b) & 0xFF00 != 0)
def _aby(c):
    b = c.rd16(c.pc); c.pc = (c.pc + 2) & 0xFFFF; a = (b + c.y) & 0xFFFF
    return a, int((a ^ b) & 0xFF00 != 0)
def _izx(c):
    z = (c.rd(c.pc) + c.x) & 0xFF; c.pc = (c.pc + 1) & 0xFFFF
    return c.mem[z] | c.mem[(z + 1) & 0xFF] << 8, 0
def _izy(c):
    z = c.rd(c.pc); c.pc = (c.pc + 1) & 0xFFFF
    b = c.mem[z] | c.mem[(z + 1) & 0xFF] << 8; a = (b + c.y) & 0xFFFF
    return a, int((a ^ b) & 0xFF00 != 0)
def _ind(c):
    p = c.rd16(c.pc); c.pc = (c.pc + 2) & 0xFFFF
    return c.rd(p) | c.rd((p & 0xFF00) | ((p + 1) & 0xFF)) << 8, 0   # NMOS page bug
def _rel(c):
    o = c.rd(c.pc); c.pc = (c.pc + 1) & 0xFFFF
    return (c.pc + (o - 256 if o > 127 else o)) & 0xFFFF, 0


_MODES = {"imp": _imp, "acc": _imp, "imm": _imm, "zp": _zp, "zpx": _zpx, "zpy": _zpy,
          "abs": _abs, "abx": _abx, "aby": _aby, "izx": _izx, "izy": _izy, "ind": _ind, "rel": _rel}


# --- instructions --------------------------------------------------------------
def _val(c, a, mode):
    return c.a if mode == "acc" else c.rd(a)

def _store(c, a, mode, v):
    if mode == "acc":
        c.a = v
    else:
        c.wr(a, v)

def _adc(c, v):
    if c.p & D:
        lo = (c.a & 0x0F) + (v & 0x0F) + (c.p & C)
        hi = (c.a >> 4) + (v >> 4) + (lo > 9)
        if lo > 9: lo += 6
        c.flag(Z, ((c.a + v + (c.p & C)) & 0xFF) == 0)
        c.flag(N, hi & 8); c.flag(V, (~(c.a ^ v) & (c.a ^ (hi << 4)) & 0x80))
        if hi > 9: hi += 6
        c.flag(C, hi > 15)
        c.a = ((hi << 4) | (lo & 0x0F)) & 0xFF
    else:
        r = c.a + v + (c.p & C)
        c.flag(C, r > 0xFF); c.flag(V, (~(c.a ^ v) & (c.a ^ r) & 0x80))
        c.a = c.nz(r & 0xFF)

def _sbc(c, v):
    if c.p & D:
        r = c.a - v - (1 - (c.p & C))
        lo = (c.a & 0x0F) - (v & 0x0F) - (1 - (c.p & C))
        hi = (c.a >> 4) - (v >> 4) - (lo < 0)
        if lo < 0: lo -= 6
        if hi < 0: hi -= 6
        c.flag(C, r >= 0); c.flag(V, ((c.a ^ v) & (c.a ^ r) & 0x80)); c.nz(r & 0xFF)
        c.a = ((hi << 4) | (lo & 0x0F)) & 0xFF
    else:
        _adc(c, v ^ 0xFF)

def _cmp(c, reg, v):
    r = reg - v
    c.flag(C, r >= 0); c.nz(r & 0xFF)

def _branch(c, a, cond):
    if cond:
        c.cycles += 1 + int((a ^ c.pc) & 0xFF00 != 0)
        c.pc = a

def _op_lda(c, a, m, e): c.a = c.nz(c.rd(a)); c.cycles += e
def _op_ldx(c, a, m, e): c.x = c.nz(c.rd(a)); c.cycles += e
def _op_ldy(c, a, m, e): c.y = c.nz(c.rd(a)); c.cycles += e
def _op_sta(c, a, m, e): c.wr(a, c.a)
def _op_stx(c, a, m, e): c.wr(a, c.x)
def _op_sty(c, a, m, e): c.wr(a, c.y)
def _op_adc(c, a, m, e): _adc(c, c.rd(a)); c.cycles += e
def _op_sbc(c, a, m, e): _sbc(c, c.rd(a)); c.cycles += e
def _op_and(c, a, m, e): c.a = c.nz(c.a & c.rd(a)); c.cycles += e
def _op_ora(c, a, m, e): c.a = c.nz(c.a | c.rd(a)); c.cycles += e
def _op_eor(c, a, m, e): c.a = c.nz(c.a ^ c.rd(a)); c.cycles += e
def _op_cmp(c, a, m, e): _cmp(c, c.a, c.rd(a)); c.cycles += e
def _op_cpx(c, a, m, e): _cmp(c, c.x, c.rd(a))
def _op_cpy(c, a, m, e): _cmp(c, c.y, c.rd(a))
def _op_bit(c, a, m, e):
    v = c.rd(a); c.flag(Z, (c.a & v) == 0); c.flag(N, v & N); c.flag(V, v & V)
def _op_inc(c, a, m, e): c.wr(a, c.nz((c.rd(a) + 1) & 0xFF))
def _op_dec(c, a, m, e): c.wr(a, c.nz((c.rd(a) - 1) & 0xFF))
def _op_inx(c, a, m, e): c.x = c.nz((c.x + 1) & 0xFF)
def _op_iny(c, a, m, e): c.y = c.nz((c.y + 1) & 0xFF)
def _op_dex(c, a, m, e): c.x = c.nz((c.x - 1) & 0xFF)
def _op_dey(c, a, m, e): c.y = c.nz((c.y - 1) & 0xFF)
def _op_asl(c, a, m, e):
    v = _val(c, a, m); c.flag(C, v & 0x80); _store(c, a, m, c.nz((v << 1) & 0xFF))
def _op_lsr(c, a, m, e):
    v = _val(c, a, m); c.flag(C, v & 1); _store(c, a, m, c.nz(v >> 1))
def _op_rol(c, a, m, e):
    v = _val(c, a, m); r = ((v << 1) | (c.p & C)) & 0xFF; c.flag(C, v & 0x80); _store(c, a, m, c.nz(r))
def _op_ror(c, a, m, e):
    v = _val(c, a, m); r = (v >> 1) | ((c.p & C) << 7); c.flag(C, v & 1); _store(c, a, m, c.nz(r))
def _op_tax(c, a, m, e): c.x = c.nz(c.a)
def _op_tay(c, a, m, e): c.y = c.nz(c.a)
def _op_txa(c, a, m, e): c.a = c.nz(c.x)
def _op_tya(c, a, m, e): c.a = c.nz(c.y)
def _op_tsx(c, a, m, e): c.x = c.nz(c.sp)
def _op_txs(c, a, m, e): c.sp = c.x
def _op_pha(c, a, m, e): c.push(c.a)
def _op_php(c, a, m, e): c.push(c.p | B | U)
def _op_pla(c, a, m, e): c.a = c.nz(c.pull())
def _op_plp(c, a, m, e): c.p = (c.pull() & ~B) | U
def _op_jmp(c, a, m, e): c.pc = a
def _op_jsr(c, a, m, e):
    r = (c.pc - 1) & 0xFFFF; c.push(r >> 8); c.push(r); c.pc = a
def _op_rts(c, a, m, e): c.pc = ((c.pull() | c.pull() << 8) + 1) & 0xFFFF
def _op_rti(c, a, m, e): c.p = (c.pull() & ~B) | U; c.pc = c.pull() | c.pull() << 8
def _op_brk(c, a, m, e): raise RuntimeError(f"BRK at ${(c.pc - 1) & 0xFFFF:04X}")
def _op_nop(c, a, m, e): pass
def _op_clc(c, a, m, e): c.flag(C, 0)
def _op_sec(c, a, m, e): c.flag(C, 1)
def _op_cli(c, a, m, e): c.flag(I, 0)
def _op_sei(c, a, m, e): c.flag(I, 1)
def _op_cld(c, a, m, e): c.flag(D, 0)
def _op_sed(c, a, m, e): c.flag(D, 1)
def _op_clv(c, a, m, e): c.flag(V, 0)
def _op_bpl(c, a, m, e): _branch(c, a, not c.p & N)
def _op_bmi(c, a, m, e): _branch(c, a, c.p & N)
def _op_bvc(c, a, m, e): _branch(c, a, not c.p & V)
def _op_bvs(c, a, m, e): _branch(c, a, c.p & V)
def _op_bcc(c, a, m, e): _branch(c, a, not c.p & C)
def _op_bcs(c, a, m, e): _branch(c, a, c.p & C)
def _op_bne(c, a, m, e): _branch(c, a, not c.p & Z)
def _op_beq(c, a, m, e): _branch(c, a, c.p & Z)


# opcode: (mnemonic, mode, base cycles)
_TABLE = """
69 adc imm 2|65 adc zp 3|75 adc zpx 4|6D adc abs 4|7D adc abx 4|79 adc aby 4|61 adc izx 6|71 adc izy 5
29 and imm 2|25 and zp 3|35 and zpx 4|2D and abs 4|3D and abx 4|39 and aby 4|21 and izx 6|31 and izy 5
0A asl acc 2|06 asl zp 5|16 asl zpx 6|0E asl abs 6|1E asl abx 7
90 bcc rel 2|B0 bcs rel 2|F0 beq rel 2|30 bmi rel 2|D0 bne rel 2|10 bpl rel 2|50 bvc rel 2|70 bvs rel 2
24 bit zp 3|2C bit abs 4|00 brk imp 7
18 clc imp 2|D8 cld imp 2|58 cli imp 2|B8 clv imp 2
C9 cmp imm 2|C5 cmp zp 3|D5 cmp zpx 4|CD cmp abs 4|DD cmp abx 4|D9 cmp aby 4|C1 cmp izx 6|D1 cmp izy 5
E0 cpx imm 2|E4 cpx zp 3|EC cpx abs 4|C0 cpy imm 2|C4 cpy zp 3|CC cpy abs 4
C6 dec zp 5|D6 dec zpx 6|CE dec abs 6|DE dec abx 7|CA dex imp 2|88 dey imp 2
49 eor imm 2|45 eor zp 3|55 eor zpx 4|4D eor abs 4|5D eor abx 4|59 eor aby 4|41 eor izx 6|51 eor izy 5
E6 inc zp 5|F6 inc zpx 6|EE inc abs 6|FE inc abx 7|E8 inx imp 2|C8 iny imp 2
4C jmp abs 3|6C jmp ind 5|20 jsr abs 6
A9 lda imm 2|A5 lda zp 3|B5 lda zpx 4|AD lda abs 4|BD lda abx 4|B9 lda aby 4|A1 lda izx 6|B1 lda izy 5
A2 ldx imm 2|A6 ldx zp 3|B6 ldx zpy 4|AE ldx abs 4|BE ldx aby 4
A0 ldy imm 2|A4 ldy zp 3|B4 ldy zpx 4|AC ldy abs 4|BC ldy abx 4
4A lsr acc 2|46 lsr zp 5|56 lsr zpx 6|4E lsr abs 6|5E lsr abx 7|EA nop imp 2
09 ora imm 2|05 ora zp 3|15 ora zpx 4|0D ora abs 4|1D ora abx 4|19 ora aby 4|01 ora izx 6|11 ora izy 5
48 pha imp 3|08 php imp 3|68 pla imp 4|28 plp imp 4
2A rol acc 2|26 rol zp 5|36 rol zpx 6|2E rol abs 6|3E rol abx 7
6A ror acc 2|66 ror zp 5|76 ror zpx 6|6E ror abs 6|7E ror abx 7
40 rti imp 6|60 rts imp 6
E9 sbc imm 2|E5 sbc zp 3|F5 sbc zpx 4|ED sbc abs 4|FD sbc abx 4|F9 sbc aby 4|E1 sbc izx 6|F1 sbc izy 5
38 sec imp 2|F8 sed imp 2|78 sei imp 2
85 sta zp 3|95 sta zpx 4|8D sta abs 4|9D sta abx 5|99 sta aby 5|81 sta izx 6|91 sta izy 6
86 stx zp 3|96 stx zpy 4|8E stx abs 4|84 sty zp 3|94 sty zpx 4|8C sty abs 4
AA tax imp 2|A8 tay imp 2|BA tsx imp 2|8A txa imp 2|9A txs imp 2|98 tya imp 2
"""
_OPS = {}
for _item in _TABLE.replace("\n", "|").split("|"):
    if _item.strip():
        _op, _mn, _mode, _cyc = _item.split()
        _OPS[int(_op, 16)] = (globals()["_op_" + _mn], _mode, int(_cyc))
