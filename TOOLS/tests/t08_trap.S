# t08_trap : synchronous exceptions (spec 6, 12 : T01-T07)
#   handler logs mcause / mepc / mtval in x20 / x21 / x22, counts in x23,
#   returns to mepc + 4 (cause 1 : to the address saved in x24)
#   x20-x27 belong to the handler, x30/x31 to the CHECK macro
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        la      x5, handler
        csrw    mtvec, x5
        li      x23, 0
        li      x28, 0x10000000
        sw      x0, 0(x28)
        sw      x0, 4(x28)

        # minstret across a trap : the trapped ecall is not counted (value compared via trace)
        csrr    x10, minstret
        ecall
        csrr    x11, minstret
        sub     x12, x11, x10           # 1 (csrr) + 9 handler instructions incl. mret
        CHECK(x12, 10)
        # T01 ecall
t01:    ecall
        CHECK(x20, 11)
        la      x6, t01
        sub     x7, x21, x6             ; CHECK(x7, 0)
        CHECK(x22, 0)
        # T02 ebreak : mtval = pc
t02:    ebreak
        CHECK(x20, 3)
        la      x6, t02
        sub     x7, x21, x6             ; CHECK(x7, 0)
        sub     x7, x22, x6             ; CHECK(x7, 0)
        # T03 illegal : mtval = instruction bits
        li      x8, 0
        addi    x9, x0, 7               # older : must still write back
t03:    .word   0xffffffff
        addi    x8, x8, 1               # younger : executed exactly once (after return)
        CHECK(x9, 7)
        CHECK(x8, 1)
        CHECK(x20, 2)
        CHECK(x22, 0xffffffff)
        csrr    x10, 0xf15              # mconfigptr : not implemented
        CHECK(x20, 2)
        CHECK(x22, 0xf1502573)
        csrw    mhartid, x5             # write to read-only CSR
        CHECK(x20, 2)
        csrr    x10, mhartid            # read is fine
        CHECK(x10, 0)
        .word   0x0000100f              # fence.i : Zifencei not implemented
        CHECK(x20, 2)
        CHECK(x23, 7)
        # T04 load / store misaligned
        li      x11, 0x10000002
        lw      x12, 0(x11)             ; CHECK(x20, 4) ; CHECK(x22, 0x10000002)
        lh      x12, 1(x11)             ; CHECK(x20, 4) ; CHECK(x22, 0x10000003)
        sw      x12, 0(x11)             ; CHECK(x20, 6)
        sh      x12, -1(x11)            ; CHECK(x20, 6) ; CHECK(x22, 0x10000001)
        lw      x13, 4(x28)             ; CHECK(x13, 0)          # misaligned store wrote nothing
        lhu     x13, 0(x11)             ; CHECK(x13, 0)          # aligned half ok
        # T05 access fault
        li      x14, 0x20000000
        lw      x15, 0(x14)             ; CHECK(x20, 5) ; CHECK(x22, 0x20000000)
        sw      x15, 0x100(x0)          ; CHECK(x20, 7) ; CHECK(x22, 0x100)          # ROM write
        li      x14, 0x40003000
        sb      x15, 0(x14)             ; CHECK(x20, 7)                               # sub-word TEST write
        li      x14, 0x10000400         # one past RAM
        lb      x15, 0(x14)             ; CHECK(x20, 5)
        sw      x0, -4(x14)             # last RAM word : not a fault
        lw      x15, -4(x14)            ; CHECK(x15, 0)
        # T06 instruction address misaligned : jump does not happen, rd not written
        li      x16, 0x55
        la      x17, t06b
        addi    x17, x17, 2
t06:    jalr    x16, 0(x17)
        CHECK(x20, 0)
        CHECK(x16, 0x55)
        la      x6, t06
        sub     x7, x21, x6             ; CHECK(x7, 0)
        sub     x7, x22, x17            ; CHECK(x7, 0)
        beq     x0, x0, .+6             ; CHECK(x20, 0)
        jal     x16, .+10               ; CHECK(x20, 0) ; CHECK(x16, 0x55)
t06b:   nop
        # T06b instruction access fault : PC outside ROM
        la      x24, 1f
        li      x18, 0x2000
        jalr    x0, 0(x18)
1:      CHECK(x20, 1)
        CHECK(x21, 0x2000)
        CHECK(x22, 0x2000)
        # T07 trap right after a load-use pair and a taken branch
        sw      x9, 0(x28)
        lw      x19, 0(x28)
        addi    x19, x19, 1
        ecall
        CHECK(x19, 8)
        beq     x0, x0, 2f
        nop
2:      ebreak
        CHECK(x20, 3)
        # mstatus after trap + mret : MIE 0 (MPIE was 0), MPIE 1 (mret sets it), MPP 11
        csrr    x10, mstatus
        CHECK(x10, 0x1880)
        PASS

handler:
        csrr    x20, mcause
        csrr    x21, mepc
        csrr    x22, mtval
        addi    x23, x23, 1
        li      x25, 1
        beq     x20, x25, 3f
        addi    x26, x21, 4
        csrw    mepc, x26
        mret
3:      csrw    mepc, x24
        mret
