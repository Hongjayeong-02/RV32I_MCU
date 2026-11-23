# t02_fwd : data hazards (spec 12, H01-H07)
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        li      sp, 0x10000000
        # H01 EX/MEM -> EX (back to back)
        li      x1, 10
        addi    x12, x1, 1
        addi    x13, x12, 1
        add     x14, x13, x12           ; CHECK(x14, 23)
        # H02 MEM/WB -> EX (one gap)
        li      x5, 100
        nop
        addi    x6, x5, 5               ; CHECK(x6, 105)
        # priority : EX/MEM must win over MEM/WB for the same rd
        li      x7, 1
        li      x7, 2
        addi    x8, x7, 0               ; CHECK(x8, 2)
        # H03 WB -> ID write-first bypass (two gaps)
        li      x9, 77
        nop
        nop
        addi    x10, x9, 0              ; CHECK(x10, 77)
        # H04 load-use (1 bubble), both operands, and load -> load address
        li      x11, 0x1234
        sw      x11, 0(sp)
        sw      sp, 4(sp)
        lw      x12, 0(sp)
        addi    x13, x12, 1             ; CHECK(x13, 0x1235)
        lw      x14, 0(sp)
        add     x15, x14, x14           ; CHECK(x15, 0x2468)
        lw      x16, 4(sp)
        lw      x17, 0(x16)             ; CHECK(x17, 0x1234)
        lw      x18, 0(sp)
        nop
        addi    x19, x18, 2             ; CHECK(x19, 0x1236)
        # H05 store data / store address forwarding
        li      x20, 0x55aa
        sw      x20, 8(sp)
        addi    x21, sp, 12
        sw      x20, 0(x21)
        lw      x22, 8(sp)              ; CHECK(x22, 0x55aa)
        lw      x23, 12(sp)             ; CHECK(x23, 0x55aa)
        lw      x24, 0(sp)
        sw      x24, 16(sp)             # load -> store data (load-use)
        lw      x25, 16(sp)             ; CHECK(x25, 0x1234)
        # H06 branch compare / jalr base forwarding
        li      x26, 3
        li      x27, 3
        bne     x26, x27, fail
        lw      x28, 0(sp)
        beq     x28, x11, 2f            # load -> branch (load-use)
        j       fail
2:      la      x29, 3f
        jalr    x1, 0(x29)
        j       fail
3:      # H07 x0 is never forwarded
        li      x27, 9
        li      x0, 5
        addi    x27, x0, 0              ; CHECK(x27, 0)
        lw      x0, 0(sp)
        addi    x27, x0, 0              ; CHECK(x27, 0)
        PASS
fail:   li      x31, 0x40003000
        sw      zero, 0(x31)
4:      j       4b
