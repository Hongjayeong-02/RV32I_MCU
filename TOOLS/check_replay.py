#!/usr/bin/env python3
"""
check_replay.py : compare an RTL run with the ISS when the ISS cannot predict
                  everything by itself (peripherals, asynchronous interrupts)  (spec 12, M3)

  The SoC testbench (tb_mcu, replay mode) writes
      <run>.trace   one line per commit, same format as rv32_iss.py
      <run>.ev      "T <pc> <cause>"       trap taken by the RTL
                    "C <pc> <rdWe> <rdVal>" commit
  The ISS is then stepped in RTL order :
      - an interrupt is injected exactly where the RTL took it (pc must match)
      - a synchronous trap must also happen in the ISS at the same pc / cause
      - a value the ISS cannot know (UART / GPIO / TIMER read, mcycle) is taken
        from the RTL commit ; nothing else is
      - every commit line (pc, inst, rd write, store address / data) must match
  So the checker trusts the RTL only for *when* an interrupt came and *what* a
  peripheral returned ; control flow, ALU results, CSR effects, stores and
  exception behaviour are all re-computed by the ISS.

usage: check_replay.py rom.bin run.trace run.ev [--name test]
works with python 3.6+
"""
import sys, os, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rv32_iss as I


class ReplayIss(I.Iss):
        def step_commit(self, ext):
                """execute one instruction that the RTL committed ; ext = RTL rd value"""
                n = len(self.trace)
                pc = self.pc
                try:
                        self.execute(pc)
                except I.Trap as t:
                        return 'ISS trapped (cause %d) where the RTL committed' % t.cause
                if len(self.trace) != n + 1:
                        return 'no commit record'
                r = list(self.trace[-1])
                # r = pc, inst, rdWe, rd, rdVal, ncRd, stWe, stSz, stA, stD, ncSt
                if r[2] and r[5]:                       # value unknown to the ISS -> take the RTL one
                        r[4], r[5] = ext, False
                        self.x[r[3]] = ext
                        self.taint[r[3]] = False
                        self.mmioReads += 1
                if r[10]:
                        return 'store of an unknown value (should not happen after replay)'
                self.trace[-1] = tuple(r)
                return None


def main():
        ap = argparse.ArgumentParser()
        ap.add_argument('rom_bin')
        ap.add_argument('trace')
        ap.add_argument('events')
        ap.add_argument('--name', default='?')
        a = ap.parse_args()

        iss = ReplayIss(open(a.rom_bin, 'rb').read())
        iss.mmioReads = 0
        rtl = [l.rstrip('\n') for l in open(a.trace)]
        ev = [l.split() for l in open(a.events) if l.strip()]

        err = []
        nC = nT = nI = 0
        for e in ev:
                if iss.halted:
                        break
                if e[0] == 'T':
                        pc, cause = int(e[1], 16), int(e[2], 16)
                        if iss.pc != pc:
                                err.append('trap at %08x but ISS pc=%08x' % (pc, iss.pc))
                                break
                        if cause >> 31:
                                iss.take_trap(cause, 0, pc)
                                nI += 1
                        else:
                                before = iss.nTraps
                                try:
                                        iss.execute(pc)
                                        err.append('RTL trap cause %d at %08x, ISS executed it' % (cause, pc))
                                        break
                                except I.Trap as t:
                                        iss.take_trap(t.cause, t.tval, pc)
                                        if t.cause != cause:
                                                err.append('trap cause RTL %d ISS %d at %08x' % (cause, t.cause, pc))
                                                break
                        nT += 1
                else:
                        pc, ext = int(e[1], 16), int(e[3], 16)
                        if iss.pc != pc:
                                err.append('commit #%d pc RTL %08x ISS %08x' % (nC, pc, iss.pc))
                                break
                        try:
                                m = iss.step_commit(ext)
                        except I.IssError as x:
                                m = 'ISS error: %s' % x
                        if m:
                                err.append('commit #%d pc %08x : %s' % (nC, pc, m))
                                break
                        exp = I.fmt_line(iss.trace[-1])
                        got = rtl[nC] if nC < len(rtl) else '<missing>'
                        if exp != got:
                                err.append('commit #%d\n      ISS %s\n      RTL %s' % (nC, exp, got))
                                if len(err) >= 5:
                                        break
                        nC += 1

        ok_halt = iss.halted and iss.passed
        print('PASS: R1 replay commit trace == ISS (%d commits, %d traps of which %d interrupts, %d peripheral/mcycle reads)'
              % (nC, nT, nI, iss.mmioReads) if not err else 'FAIL: R1 replay commit trace == ISS')
        for m in err:
                print('  ' + m)
        print('PASS: R2 ISS reached TEST_STATUS = PASS' if ok_halt else 'FAIL: R2 ISS reached TEST_STATUS = PASS')
        if not err and ok_halt:
                print('REPLAY %s ALL PASS  commits=%d traps=%d ints=%d mmio=%d' % (a.name, nC, nT, nI, iss.mmioReads))
                sys.exit(0)
        print('REPLAY %s FAIL' % a.name)
        sys.exit(1)


if __name__ == '__main__':
        main()
