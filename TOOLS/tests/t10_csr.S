# t10_csr : CSR read / write rules, read-only fields, counters (spec 6)
#include "test_macros.h"
        .section .text.init
        .globl _start
_start:
        # misa / ids
        csrr    x5, misa                ; CHECK(x5, 0x40000100)
        csrw    misa, x0                # WARL : ignored
        csrr    x5, misa                ; CHECK(x5, 0x40000100)
        csrr    x5, mvendorid           ; CHECK(x5, 0)
        csrr    x5, marchid             ; CHECK(x5, 0)
        csrr    x5, mimpid              ; CHECK(x5, 0)
        # mscratch : RW, back to back (CSR -> CSR, CSR -> ALU load-use)
        li      x6, 0x12345678
        csrw    mscratch, x6
        csrr    x7, mscratch
        addi    x8, x7, 1               ; CHECK(x8, 0x12345679)
        csrrw   x9, mscratch, x0        ; CHECK(x9, 0x12345678)
        csrr    x9, mscratch            ; CHECK(x9, 0)
        csrrwi  x9, mscratch, 21        ; CHECK(x9, 0)
        csrrsi  x9, mscratch, 8         ; CHECK(x9, 21)
        csrrci  x9, mscratch, 1         ; CHECK(x9, 29)
        csrr    x9, mscratch            ; CHECK(x9, 28)
        li      x10, 0xf0
        csrrs   x9, mscratch, x10       ; CHECK(x9, 28)
        csrrc   x9, mscratch, x10       ; CHECK(x9, 0xfc)
        csrr    x9, mscratch            ; CHECK(x9, 0x0c)
        csrrs   x9, mscratch, x0        # rs1 = x0 : read only
        csrrc   x9, mscratch, x0
        csrrsi  x9, mscratch, 0
        csrr    x9, mscratch            ; CHECK(x9, 0x0c)
        # mstatus : only MIE / MPIE writable, MPP reads 11
        li      x11, -1
        csrw    mstatus, x11
        csrr    x12, mstatus            ; CHECK(x12, 0x1888)
        csrw    mstatus, x0
        csrr    x12, mstatus            ; CHECK(x12, 0x1800)
        # mtvec / mepc : [1:0] = 0 ; mcause : bits 31 and 3:0 ; mtval : full
        csrw    mtvec, x11
        csrr    x13, mtvec              ; CHECK(x13, 0xfffffffc)
        csrw    mepc, x11
        csrr    x13, mepc               ; CHECK(x13, 0xfffffffc)
        csrw    mcause, x11
        csrr    x13, mcause             ; CHECK(x13, 0x8000000f)
        csrw    mtval, x11
        csrr    x13, mtval              ; CHECK(x13, 0xffffffff)
        csrw    mie, x11
        csrr    x13, mie                ; CHECK(x13, 0x880)
        csrw    mie, x0
        csrw    mip, x11                # ignored
        csrr    x13, mip                ; CHECK(x13, 0)
        # minstret : exact count of retired instructions
        csrr    x14, minstret
        nop
        nop
        nop
        csrr    x15, minstret
        sub     x16, x15, x14           ; CHECK(x16, 4)
        li      x17, 100
        csrw    minstret, x17           # written value is what the next instruction sees
        csrr    x18, minstret           ; CHECK(x18, 100)
        csrr    x18, minstreth          ; CHECK(x18, 0)
        li      x17, -2
        csrw    minstret, x17
        nop
        nop
        csrr    x18, minstreth          ; CHECK(x18, 1)        # carry into the upper half
        csrw    minstreth, x0
        # mcycle : value depends on the pipeline, the ISS marks it "no compare"
        csrr    x19, mcycle
        csrr    x19, mcycleh

        PASS
