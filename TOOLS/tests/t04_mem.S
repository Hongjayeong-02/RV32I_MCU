# t04_mem : loads / stores on every byte lane, sign / zero extension, ROM data
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        li      x28, 0x10000100
        li      x1, 0x8899aabb
        sw      x1, 0(x28)
        lb      x2, 0(x28)               ; CHECK(x2, 0xffffffbb)
        lb      x3, 1(x28)               ; CHECK(x3, 0xffffffaa)
        lb      x4, 2(x28)               ; CHECK(x4, 0xffffff99)
        lb      x5, 3(x28)               ; CHECK(x5, 0xffffff88)
        lbu     x6, 0(x28)               ; CHECK(x6, 0xbb)
        lbu     x7, 3(x28)               ; CHECK(x7, 0x88)
        lh      x8, 0(x28)               ; CHECK(x8, 0xffffaabb)
        lh      x9, 2(x28)               ; CHECK(x9, 0xffff8899)
        lhu     x10, 0(x28)              ; CHECK(x10, 0xaabb)
        lhu     x11, 2(x28)              ; CHECK(x11, 0x8899)
        li      x12, 0x7f
        sb      x12, 4(x28)
        li      x12, 0x01
        sb      x12, 5(x28)
        li      x12, 0x123456ee         # only low byte stored
        sb      x12, 6(x28)
        sb      x0, 7(x28)
        lw      x13, 4(x28)              ; CHECK(x13, 0x00ee017f)
        lb      x14, 4(x28)              ; CHECK(x14, 0x7f)
        li      x15, 0xbeefcafe
        sh      x15, 8(x28)
        sh      x0, 10(x28)
        lw      x16, 8(x28)              ; CHECK(x16, 0x0000cafe)
        sh      x15, 10(x28)
        lw      x17, 8(x28)              ; CHECK(x17, 0xcafecafe)
        # negative offset, RAM bottom and top word
        li      x18, 0x10000000
        li      x19, 0x11111111
        sw      x19, 0(x18)
        sw      x19, 1020(x18)
        addi    x20, x18, 1024
        lw      x21, -4(x20)            ; CHECK(x21, 0x11111111)
        lw      x22, 0(x18)             ; CHECK(x22, 0x11111111)
        # ROM data (.rodata through port B)
        la      x23, table
        lw      x24, 0(x23)             ; CHECK(x24, 0xdeadbeef)
        lbu     x25, 4(x23)             ; CHECK(x25, 0x11)
        lh      x26, 6(x23)             ; CHECK(x26, 0xffff8844)
        lw      x27, 0(x0)              # first instruction word of the program
        PASS

        .section .rodata
        .align 2
table:  .word   0xdeadbeef
        .byte   0x11, 0x22, 0x44, 0x88
