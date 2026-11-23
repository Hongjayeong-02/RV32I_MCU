# t01_alu : every RV32I ALU instruction, corner operands, results checked in software
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        li      x1, 0x7fffffff
        li      x2, 0x80000000
        li      x3, -1
        li      x4, 5
        add     x10, x1, x4             ; CHECK(x10, 0x80000004)
        sub     x11, x2, x4             ; CHECK(x11, 0x7ffffffb)
        sub     x12, x4, x3             ; CHECK(x12, 6)
        addi    x13, x3, -2048          ; CHECK(x13, 0xfffff7ff)
        addi    x14, x0, 2047           ; CHECK(x14, 2047)
        slt     x15, x2, x1             ; CHECK(x15, 1)
        slt     x16, x1, x2             ; CHECK(x16, 0)
        sltu    x17, x1, x2             ; CHECK(x17, 1)
        sltu    x18, x3, x4             ; CHECK(x18, 0)
        slti    x19, x3, 0              ; CHECK(x19, 1)
        sltiu   x20, x4, -1             ; CHECK(x20, 1)
        sltiu   x21, x0, 1              ; CHECK(x21, 1)
        xor     x22, x1, x3             ; CHECK(x22, 0x80000000)
        xori    x23, x4, -1             ; CHECK(x23, 0xfffffffa)
        or      x24, x2, x4             ; CHECK(x24, 0x80000005)
        ori     x25, x0, 0x555          ; CHECK(x25, 0x555)
        and     x26, x3, x4             ; CHECK(x26, 5)
        andi    x27, x1, -16            ; CHECK(x27, 0x7ffffff0)
        sll     x28, x4, x4             ; CHECK(x28, 0xa0)
        li      x5, 33
        sll     x29, x4, x5             ; CHECK(x29, 10)
        slli    x9, x3, 31              ; CHECK(x9, 0x80000000)
        srl     x10, x2, x4             ; CHECK(x10, 0x04000000)
        sra     x11, x2, x4             ; CHECK(x11, 0xfc000000)
        srli    x12, x3, 28             ; CHECK(x12, 0xf)
        srai    x13, x3, 31             ; CHECK(x13, 0xffffffff)
        srai    x14, x1, 30             ; CHECK(x14, 1)
        lui     x15, 0xabcde            ; CHECK(x15, 0xabcde000)
        auipc   x16, 0
        auipc   x17, 1
        sub     x18, x17, x16           ; CHECK(x18, 0x1004)
        add     x0, x1, x1              ; CHECK(x0, 0)
        fence
        PASS
