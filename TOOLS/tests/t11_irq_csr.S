# t11_irq_csr : an interrupt taken on a CSR write must not let that write happen
#   (found by mutation testing : "trapping instruction still writes CSR" was not caught)
#   rv32_csr gives the trap priority over the write for the CSRs in the state block,
#   but the counters (minstret / minstreth / mcycle) are written in their own block,
#   so an interrupted "csrw minstret" is the only place where the bug can show.
#   TEST_IRQ (0x4000_3008) bit1 -> MTIP : taken at the instruction right after the store.
#   handler reads minstret / minstreth into x18 / x17 : they must not hold the written value.
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        la      x5, handler
        csrw    mtvec, x5
        li      x27, 0x40003008         # TEST_IRQ
        li      x23, 0                  # interrupt count
        li      x5, 0x80
        csrw    mie, x5                 # MTIE
        csrsi   mstatus, 8              # MIE
        # A : interrupted csrw minstret
        li      x13, 0x00ABCDE0
        li      x6, 2
        mv      x22, x6
        sw      x6, 0(x27)
a1:     csrw    minstret, x13           # interrupted : executed only after mret
        CHECK(x23, 1)
        CHECK(x20, 0x80000007)
        la      x9, a1
        sub     x9, x21, x9             ; CHECK(x9, 0)
        sub     x15, x18, x13           # a leaked write leaves minstret just above x13
        sltiu   x15, x15, 16            ; CHECK(x15, 0)
        csrr    x14, minstret
        sub     x14, x14, x13           # written after mret : only a few instructions since
        sltiu   x15, x14, 16            ; CHECK(x15, 1)
        # B : interrupted csrw minstreth
        li      x13, 0x00005A5A
        li      x6, 2
        mv      x22, x6
        sw      x6, 0(x27)
b1:     csrw    minstreth, x13          # interrupted : executed only after mret
        CHECK(x23, 2)
        la      x9, b1
        sub     x9, x21, x9             ; CHECK(x9, 0)
        beq     x17, x13, fail          # handler must see the old upper half
        csrr    x14, minstreth
        CHECK(x14, 0x00005A5A)
        li      x22, 0
        sw      x0, 0(x27)
        PASS
fail:   li      x31, 0x40003000
        sw      x0, 0(x31)
1:      j       1b

handler:
        csrr    x20, mcause
        csrr    x21, mepc
        csrr    x18, minstret
        csrr    x17, minstreth
        addi    x23, x23, 1
        andi    x22, x22, 1             # MTI : clear bit1
        sw      x22, 0(x27)
        mret
