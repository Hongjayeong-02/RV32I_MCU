#!/usr/bin/env python3
"""
rv32_iss.py : instruction-set simulator = golden model for the RTL commit trace.

  ISA      : RV32I (40) + Zicsr (6) + MRET, machine mode only (spec 4, 6)
  traps    : precise ; interrupt checked before every instruction (an instruction
             that is interrupted is not executed, mepc = its pc)
             sync causes 0,1,2,3,4,5,6,7,11 ; interrupts MEI (11) > MTI (7)
  memory   : ROM  0x0000_0000 - 0x0000_0FFF  read only
             RAM  0x1000_0000 - 0x1000_03FF  reading a never-written byte = error (RTL: X)
             APB  0x4000_0000 + dev*0x1000 + off, off < size (mcu_dbus) :
                  UART 0x20, GPIO 0x10, TIMER 0x14, TEST 0x0C ; word write only
                  TEST 0x00 STATUS (write -> halt, bit0 PASS ; read {halt, pass})
                       0x04 RESULT (RW)
                       0x08 IRQ    (RW) bit0 -> MEIP, bit1 -> MTIP
                  UART / GPIO / TIMER reads : value unknown to the ISS -> "no compare"
                  (tainted, like mcycle) ; writes have no effect in the ISS
                  (tests that need their behaviour run in replay mode, M3)
             anything else -> load / store access fault
  counters : minstret is exact (retired instructions). mcycle depends on the
             pipeline -> its read value is marked "no compare" and tainted:
             tainted values may flow into registers / store data (not compared)
             but a branch, address or CSR write that depends on them is an ISS error.
  output   : expected.trace (text) and expected.hex (8 words per commit):
             pc, inst, {noCmpRd, rdWe, 3'b0, rd}, rdVal, {noCmpSt, stWe, 6'b0, stSize},
             stAddr, stData(masked), 0

usage: rv32_iss.py rom.bin out_dir [--max N]
"""
import sys, os, argparse

ROM_BASE, ROM_SIZE = 0x0000_0000, 0x1000
RAM_BASE, RAM_SIZE = 0x1000_0000, 0x400
TEST_BASE = 0x4000_3000
APB_BASE = 0x4000_0000
APB_SIZE = {0: 0x20, 1: 0x10, 2: 0x14, 3: 0x0C}        # UART GPIO TIMER TEST
M32 = 0xFFFF_FFFF

# CSR addresses
MSTATUS, MISA, MIE, MTVEC = 0x300, 0x301, 0x304, 0x305
MSCRATCH, MEPC, MCAUSE, MTVAL, MIP = 0x340, 0x341, 0x342, 0x343, 0x344
MCYCLE, MINSTRET, MCYCLEH, MINSTRETH = 0xB00, 0xB02, 0xB80, 0xB82
MVENDORID, MARCHID, MIMPID, MHARTID = 0xF11, 0xF12, 0xF13, 0xF14
CSRS = {MSTATUS, MISA, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP,
        MCYCLE, MINSTRET, MCYCLEH, MINSTRETH, MVENDORID, MARCHID, MIMPID, MHARTID}
MISA_VAL = 0x4000_0100          # RV32, I


class IssError(Exception):
        pass


class Trap(Exception):
        def __init__(self, cause, tval):
                self.cause, self.tval = cause, tval & M32


def sx(v, bits):
        v &= (1 << bits) - 1
        return v - (1 << bits) if v >> (bits - 1) else v


class Iss:
        def __init__(self, rom):
                if len(rom) > ROM_SIZE:
                        raise IssError(f'ROM image {len(rom)} B > {ROM_SIZE} B')
                self.rom = bytearray(rom) + bytearray(ROM_SIZE - len(rom))
                self.ram = bytearray(RAM_SIZE)
                self.ramInit = bytearray(RAM_SIZE)
                self.ramTaint = bytearray(RAM_SIZE)
                self.x = [0] * 32
                self.taint = [False] * 32
                self.pc = 0
                self.halted = False
                self.passed = None
                self.result = None
                self.irq = 0                    # TEST_IRQ : bit0 MEIP, bit1 MTIP
                # CSR state
                self.mie_ = 0                   # mstatus.MIE
                self.mpie = 0
                self.mieReg = 0                 # mie register (bits 7, 11)
                self.mtvec = 0
                self.mscratch = 0
                self.mepc = 0
                self.mcause = 0
                self.mtval = 0
                self.minstret = 0
                self.trace = []
                self.nTraps = 0

        # ---------------- memory ----------------
        def load(self, addr, size, fetch=False):
                if ROM_BASE <= addr and addr + size <= ROM_BASE + ROM_SIZE:
                        return int.from_bytes(self.rom[addr:addr + size], 'little'), False
                if fetch:
                        raise Trap(1, addr)
                if RAM_BASE <= addr and addr + size <= RAM_BASE + RAM_SIZE:
                        o = addr - RAM_BASE
                        if not all(self.ramInit[o:o + size]):
                                raise IssError(f'load from uninitialized RAM {addr:08x} (RTL would read X)')
                        return int.from_bytes(self.ram[o:o + size], 'little'), any(self.ramTaint[o:o + size])
                dev, off = self.apb_dev(addr)
                if dev is not None:
                        if dev == 3:
                                w = {0: (int(self.halted) << 1) | int(bool(self.passed)),
                                     4: self.result or 0, 8: self.irq}[off & ~3]
                                return (w >> (8 * (off & 3))) & ((1 << (8 * size)) - 1), False
                        return 0, True                  # UART / GPIO / TIMER : not modelled
                raise Trap(5, addr)

        @staticmethod
        def apb_dev(addr):
                if (addr >> 14) != (APB_BASE >> 14):
                        return None, 0
                dev, off = (addr >> 12) & 3, addr & 0xFFF
                return (dev, off) if off < APB_SIZE[dev] else (None, 0)

        def store(self, addr, size, val, taint):
                val &= (1 << (8 * size)) - 1
                if RAM_BASE <= addr and addr + size <= RAM_BASE + RAM_SIZE:
                        o = addr - RAM_BASE
                        self.ram[o:o + size] = val.to_bytes(size, 'little')
                        self.ramInit[o:o + size] = b'\x01' * size
                        self.ramTaint[o:o + size] = (b'\x01' if taint else b'\x00') * size
                        return
                dev, off = self.apb_dev(addr)
                if dev is not None and size == 4:
                        if dev == 3:
                                if taint:
                                        raise IssError('tainted value written to the TEST device')
                                if off == 0:
                                        self.halted, self.passed = True, bool(val & 1)
                                elif off == 4:
                                        self.result = val
                                elif off == 8:
                                        self.irq = val & 3
                        return
                raise Trap(7, addr)             # unmapped, ROM, or sub-word to APB

        # ---------------- CSR ----------------
        def mstatus(self):
                return (self.mie_ << 3) | (self.mpie << 7) | (3 << 11)

        def mip(self):
                return ((self.irq & 1) << 11) | (((self.irq >> 1) & 1) << 7)

        def csr_read(self, a):
                """returns (value, tainted)"""
                if a == MSTATUS:   return self.mstatus(), False
                if a == MISA:      return MISA_VAL, False
                if a == MIE:       return self.mieReg, False
                if a == MTVEC:     return self.mtvec, False
                if a == MSCRATCH:  return self.mscratch, False
                if a == MEPC:      return self.mepc, False
                if a == MCAUSE:    return self.mcause, False
                if a == MTVAL:     return self.mtval, False
                if a == MIP:       return self.mip(), False
                if a == MINSTRET:  return self.minstret & M32, False
                if a == MINSTRETH: return (self.minstret >> 32) & M32, False
                if a in (MCYCLE, MCYCLEH): return 0, True
                return 0, False                 # mvendorid .. mhartid

        def csr_write(self, a, v):
                if a == MSTATUS:
                        self.mie_, self.mpie = (v >> 3) & 1, (v >> 7) & 1
                elif a == MIE:      self.mieReg = v & 0x880
                elif a == MTVEC:    self.mtvec = v & ~3 & M32
                elif a == MSCRATCH: self.mscratch = v
                elif a == MEPC:     self.mepc = v & ~3 & M32
                elif a == MCAUSE:   self.mcause = v & 0x8000_000F
                elif a == MTVAL:    self.mtval = v
                elif a == MINSTRET:  self.minstret = (self.minstret & ~M32) | v
                elif a == MINSTRETH: self.minstret = (self.minstret & M32) | (v << 32)
                elif a in (MCYCLE, MCYCLEH):
                        pass                    # value not modelled (pipeline dependent)
                # misa, mip : writes ignored (WARL)

        def take_trap(self, cause, tval, pc):
                self.mepc = pc & ~3 & M32
                self.mcause = cause
                self.mtval = tval
                self.mpie, self.mie_ = self.mie_, 0
                self.pc = self.mtvec
                self.nTraps += 1

        # ---------------- one instruction ----------------
        def step(self):
                # interrupt between instructions
                pend = self.mip() & self.mieReg
                if self.mie_ and pend:
                        cause = 0x8000_000B if pend & 0x800 else 0x8000_0007
                        self.take_trap(cause, 0, self.pc)
                        return
                pc = self.pc
                try:
                        self.execute(pc)
                except Trap as t:
                        self.take_trap(t.cause, t.tval, pc)

        def execute(self, pc):
                inst, _ = self.load(pc, 4, fetch=True)
                op = inst & 0x7F
                rd = (inst >> 7) & 31
                f3 = (inst >> 12) & 7
                rs1 = (inst >> 15) & 31
                rs2 = (inst >> 20) & 31
                f7 = inst >> 25
                a, b = self.x[rs1], self.x[rs2]
                ta, tb = self.taint[rs1], self.taint[rs2]
                immI = sx(inst >> 20, 12)
                immS = sx(((inst >> 25) << 5) | ((inst >> 7) & 31), 12)
                immB = sx(((inst >> 31) << 12) | (((inst >> 7) & 1) << 11) |
                          (((inst >> 25) & 63) << 5) | (((inst >> 8) & 15) << 1), 13)
                immU = inst & 0xFFFFF000
                immJ = sx(((inst >> 31) << 20) | (((inst >> 12) & 255) << 12) |
                          (((inst >> 20) & 1) << 11) | (((inst >> 21) & 1023) << 1), 21)

                rdVal, rdTaint = None, False
                st = None
                npc = (pc + 4) & M32
                retire = True                   # False for mret? (mret retires) -> stays True

                def illegal():
                        raise Trap(2, inst)

                def need_clean(*t):
                        if any(t):
                                raise IssError(f'tainted (mcycle) value used as branch/address/CSR at {pc:08x}')

                def jump(target):
                        if target & 3:
                                raise Trap(0, target)
                        return target

                if inst & 3 != 3:
                        illegal()
                if op == 0x37:
                        rdVal = immU
                elif op == 0x17:
                        rdVal = (pc + immU) & M32
                elif op == 0x6F:
                        npc = jump((pc + immJ) & M32)
                        rdVal = (pc + 4) & M32
                elif op == 0x67:
                        if f3: illegal()
                        need_clean(ta)
                        npc = jump((a + immI) & M32 & ~1)
                        rdVal = (pc + 4) & M32
                elif op == 0x63:
                        if f3 in (2, 3): illegal()
                        need_clean(ta, tb)
                        sa, sb = sx(a, 32), sx(b, 32)
                        cond = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}[f3]
                        if cond:
                                npc = jump((pc + immB) & M32)
                elif op == 0x03:
                        if f3 not in (0, 1, 2, 4, 5): illegal()
                        need_clean(ta)
                        addr = (a + immI) & M32
                        size = 1 << (f3 & 3)
                        if addr % size:
                                raise Trap(4, addr)
                        v, rdTaint = self.load(addr, size)
                        if f3 == 0:   v = sx(v, 8) & M32
                        elif f3 == 1: v = sx(v, 16) & M32
                        rdVal = v
                elif op == 0x23:
                        if f3 not in (0, 1, 2): illegal()
                        need_clean(ta)
                        addr = (a + immS) & M32
                        size = 1 << f3
                        if addr % size:
                                raise Trap(6, addr)
                        self.store(addr, size, b, tb)
                        st = (f3, addr, b & ((1 << (8 * size)) - 1), tb)
                elif op in (0x13, 0x33):
                        y = b if op == 0x33 else immI & M32
                        ty = tb if op == 0x33 else False
                        sh = y & 31
                        if op == 0x13 and f3 == 1 and f7 != 0: illegal()
                        if op == 0x13 and f3 == 5 and f7 not in (0, 0x20): illegal()
                        if op == 0x33 and not (f7 == 0 or (f7 == 0x20 and f3 in (0, 5))): illegal()
                        alt = (f7 == 0x20)
                        if f3 == 0:   r = (a - y) if (op == 0x33 and alt) else (a + y)
                        elif f3 == 1: r = a << sh
                        elif f3 == 2: r = int(sx(a, 32) < sx(y, 32))
                        elif f3 == 3: r = int(a < (y & M32))
                        elif f3 == 4: r = a ^ y
                        elif f3 == 5: r = (sx(a, 32) >> sh) if alt else (a >> sh)
                        elif f3 == 6: r = a | y
                        else:         r = a & y
                        rdVal, rdTaint = r & M32, ta or ty
                elif op == 0x0F:
                        if f3: illegal()                # FENCE = NOP, FENCE.I illegal
                elif op == 0x73:
                        if f3 == 0:
                                if inst == 0x0000_0073: raise Trap(11, 0)
                                if inst == 0x0010_0073: raise Trap(3, pc)
                                if inst == 0x3020_0073:         # MRET
                                        self.mie_, self.mpie = self.mpie, 1
                                        npc = self.mepc
                                else:
                                        illegal()
                        elif f3 == 4:
                                illegal()
                        else:
                                csr = inst >> 20
                                cmd = f3 & 3
                                if csr not in CSRS: illegal()
                                src, tsrc = (rs1, False) if f3 & 4 else (a, ta)
                                doRead = not (cmd == 1 and rd == 0)
                                doWrite = cmd == 1 or rs1 != 0
                                if doWrite and (csr >> 10) == 3: illegal()      # read-only
                                old, told = self.csr_read(csr) if doRead else (0, False)
                                if doWrite:
                                        need_clean(tsrc)
                                        cur = old if doRead else self.csr_read(csr)[0]
                                        if cmd != 1:
                                                need_clean(told)
                                        new = src if cmd == 1 else (cur | src) if cmd == 2 else (cur & ~src)
                                        self.csr_write(csr, new & M32)
                                        if csr in (MINSTRET, MINSTRETH):
                                                retire = False          # written value is what the next instruction sees
                                rdVal, rdTaint = old, told
                else:
                        illegal()

                rdWe = rdVal is not None and rd != 0
                if rdWe:
                        self.x[rd] = rdVal
                        self.taint[rd] = rdTaint
                self.trace.append((pc, inst, rdWe, rd if rdWe else 0, rdVal if rdWe else 0, rdWe and rdTaint,
                                   st is not None, st[0] if st else 0, st[1] if st else 0,
                                   st[2] if st else 0, bool(st and st[3])))
                if retire:
                        self.minstret = (self.minstret + 1) & ((1 << 64) - 1)
                self.pc = npc


def fmt_line(r):
        pc, inst, rdWe, rd, rdVal, ncRd, stWe, stSz, stA, stD, ncSt = r
        s = f'{pc:08x} {inst:08x}'
        if rdWe:
                s += f' x{rd:02d}=' + ('--------' if ncRd else f'{rdVal:08x}')
        if stWe:
                s += f' M[{stA:08x}]<=' + ('-' * (2 << stSz) if ncSt else f'{stD:0{2 << stSz}x}')
        return s


def main():
        ap = argparse.ArgumentParser()
        ap.add_argument('rom_bin')
        ap.add_argument('out_dir')
        ap.add_argument('--max', type=int, default=200000)
        args = ap.parse_args()
        iss = Iss(open(args.rom_bin, 'rb').read())
        try:
                while not iss.halted and len(iss.trace) < args.max:
                        iss.step()
        except IssError as e:
                print(f'ISS ERROR after {len(iss.trace)} instructions: {e}')
                sys.exit(1)
        if not iss.halted:
                print(f'ISS ERROR: no halt within {args.max} instructions (pc={iss.pc:08x})')
                sys.exit(1)
        os.makedirs(args.out_dir, exist_ok=True)
        with open(os.path.join(args.out_dir, 'expected.trace'), 'w') as f:
                for r in iss.trace:
                        f.write(fmt_line(r) + '\n')
        with open(os.path.join(args.out_dir, 'expected.hex'), 'w') as f:
                f.write(f'// {len(iss.trace)} commits x 8 words : pc inst {{ncRd,rdWe,3b0,rd}} rdVal '
                        f'{{ncSt,stWe,6b0,stSize}} stAddr stData 0\n')
                for r in iss.trace:
                        pc, inst, rdWe, rd, rdVal, ncRd, stWe, stSz, stA, stD, ncSt = r
                        for w in (pc, inst, (int(ncRd) << 9) | (int(rdWe) << 8) | rd, rdVal,
                                  (int(ncSt) << 9) | (int(stWe) << 8) | stSz, stA, stD, 0):
                                f.write(f'{w:08x}\n')
        res = 'PASS' if iss.passed else 'FAIL'
        print(f'ISS {res} : {len(iss.trace)} commits, {iss.nTraps} traps, result={iss.result}')
        sys.exit(0 if iss.passed else 2)


if __name__ == '__main__':
        main()
