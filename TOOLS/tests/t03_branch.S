# t03_branch : all branch conditions (taken / not taken), jal / jalr, loops
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        li      x1, -1
        li      x2, 1
        li      x10, 0                  # taken counter
        beq     x2, x2, 2f
        j       fail
2:      bne     x1, x2, 2f
        j       fail
2:      blt     x1, x2, 2f              # signed -1 < 1
        j       fail
2:      bge     x2, x1, 2f
        j       fail
2:      bltu    x2, x1, 2f              # unsigned 1 < 0xffffffff
        j       fail
2:      bgeu    x1, x2, 2f
        j       fail
2:      # not taken : each wrong way would jump to fail
        beq     x1, x2, fail
        bne     x2, x2, fail
        blt     x2, x1, fail
        bge     x1, x2, fail
        bltu    x1, x2, fail
        bgeu    x2, x1, fail
        bge     x2, x2, 2f              # equal -> taken
        j       fail
2:      # loop : sum 1..20
        li      x3, 20
        li      x4, 0
loop:   add     x4, x4, x3
        addi    x3, x3, -1
        bnez    x3, loop                ; CHECK(x4, 210)
        # backward branch to the next instruction-after-branch distance tests
        jal     x5, sub1
        addi    x6, x6, 1               # executed after return
        CHECK(x7, 0x99)
        CHECK(x6, 1)
        # jalr with odd target : bit 0 cleared
        la      x8, 2f
        addi    x8, x8, 1
        jalr    x9, 0(x8)
        j       fail
2:      # jal rd = x0, jalr rd = x0
        jal     x0, 2f
        j       fail
2:      la      x11, 2f
        jalr    x0, x11, 0
        j       fail
2:      # branch right after a branch
        beq     x0, x0, 2f
        beq     x0, x0, fail
2:      bne     x0, x0, fail
        beq     x0, x0, 2f
        j       fail
2:      PASS
sub1:   li      x7, 0x99
        li      x6, 0
        jalr    x0, 0(x5)               # return through x5 (jal x5)
fail:   li      t6, 0x40003000
        sw      zero, 0(t6)
4:      j       4b
