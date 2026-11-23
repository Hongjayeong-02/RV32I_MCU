# t09_irq : interrupts through the TEST_IRQ register (spec 6, 12 : T08-T10)
#   TEST_IRQ (0x4000_3008) bit0 -> MEIP, bit1 -> MTIP (testbench level sources)
#   handler logs mcause / mepc in x20 / x21, appends mcause to a RAM log,
#   clears only the bit of the cause it took (x22 = shadow of TEST_IRQ, which reads 0),
#   returns with mret (mepc unchanged)
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        la      x5, handler
        csrw    mtvec, x5
        li      x27, 0x40003008         # TEST_IRQ
        li      x28, 0x10000000         # log base
        li      x24, 0x10000000         # log pointer
        li      x23, 0                  # interrupt count
        li      x5, 0x880
        csrw    mie, x5                 # MEIE | MTIE
        # T08a : pending but mstatus.MIE = 0 -> not taken
        li      x6, 1
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
        nop
        nop
        CHECK(x23, 0)
        csrr    x7, mip
        CHECK(x7, 0x800)
        # enabling MIE -> taken at the very next instruction
        csrsi   mstatus, 8
i1:     addi    x8, x0, 1
        CHECK(x23, 1)
        CHECK(x20, 0x8000000b)
        la      x9, i1
        sub     x9, x21, x9             ; CHECK(x9, 0)
        CHECK(x8, 1)                    # interrupted instruction ran after mret
        # T08b : timer, taken right after the store that raises it
        li      x6, 2
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
i2:     addi    x8, x8, 1
        CHECK(x23, 2)
        CHECK(x20, 0x80000007)
        la      x9, i2
        sub     x9, x21, x9             ; CHECK(x9, 0)
        CHECK(x8, 2)
        # T08c : both pending -> MEI first, then MTI right after mret
        li      x6, 3
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
        nop
        CHECK(x23, 4)
        lw      x10, 8(x28)
        CHECK(x10, 0x8000000b)
        lw      x10, 12(x28)
        CHECK(x10, 0x80000007)
        # T08d : mie bit off -> not taken ; turning it on -> taken
        csrci   mie, 0                  # no change (zimm = 0 : no write)
        li      x5, 0x800
        csrc    mie, x5                 # MEIE off
        li      x6, 1
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
        nop
        CHECK(x23, 4)
        csrs    mie, x5
        nop
        CHECK(x23, 5)
        # T09 : interrupt arriving next to a taken branch, a load-use and a CSR read
        li      x6, 2
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
i3:     beq     x0, x0, 2f
        j       fail
2:      CHECK(x23, 6)
        la      x9, i3
        sub     x9, x21, x9             ; CHECK(x9, 0)       # mepc = the branch, branch then executed
        sw      x8, 16(x28)
        li      x6, 1
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
        lw      x11, 16(x28)
        addi    x11, x11, 5
        CHECK(x11, 7)
        CHECK(x23, 7)
        # interrupted CSR write must not happen before the handler (handler reads mscratch)
        csrw    mscratch, x0
        li      x13, 0x77
        li      x6, 2
        mv      x22, x6
        sw      x6, 0(x27)
        csrw    mscratch, x13           # interrupted : executed only after mret
        CHECK(x19, 0)                   # handler saw the old value
        csrr    x14, mscratch
        CHECK(x14, 0x77)
        CHECK(x23, 8)
        # T10 : inside the handler MIE = 0, MPIE = 1 ; after mret MIE = 1
        CHECK(x26, 0x1880)              # mstatus seen by the handler
        csrr    x12, mstatus
        CHECK(x12, 0x1888)
        # interrupt pending while the program writes mstatus.MIE = 0 : never taken
        csrci   mstatus, 8
        li      x6, 3
        mv      x22, x6                 # shadow of TEST_IRQ (it reads 0)
        sw      x6, 0(x27)
        nop
        nop
        CHECK(x23, 8)
        li      x22, 0
        sw      x0, 0(x27)
        PASS
fail:   li      x31, 0x40003000
        sw      x0, 0(x31)
1:      j       1b

handler:
        csrr    x20, mcause
        csrr    x21, mepc
        csrr    x26, mstatus
        csrr    x19, mscratch
        addi    x23, x23, 1
        sw      x20, 0(x24)
        addi    x24, x24, 4
        lw      x25, 0(x27)             # TEST reads 0 : just a bus read in the handler
        li      x25, 0x8000000b
        bne     x20, x25, 3f
        andi    x22, x22, 2             # MEI : clear bit0 only
        j       4f
3:      andi    x22, x22, 1             # MTI : clear bit1 only
4:      sw      x22, 0(x27)
        mret
