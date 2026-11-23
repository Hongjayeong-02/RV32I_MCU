# trap.S : trap entry for C programs (spec 9)
#   saves the 16 caller-saved registers, calls
#       uint32_t trap_handler(uint32_t mcause, uint32_t mepc)
#   writes its return value to mepc and returns with mret
        .section .text
        .align  2
        .globl  trap_entry
trap_entry:
        addi    sp, sp, -64
        sw      ra,  0(sp)
        sw      t0,  4(sp)
        sw      t1,  8(sp)
        sw      t2, 12(sp)
        sw      a0, 16(sp)
        sw      a1, 20(sp)
        sw      a2, 24(sp)
        sw      a3, 28(sp)
        sw      a4, 32(sp)
        sw      a5, 36(sp)
        sw      a6, 40(sp)
        sw      a7, 44(sp)
        sw      t3, 48(sp)
        sw      t4, 52(sp)
        sw      t5, 56(sp)
        sw      t6, 60(sp)
        csrr    a0, mcause
        csrr    a1, mepc
        call    trap_handler
        csrw    mepc, a0
        lw      ra,  0(sp)
        lw      t0,  4(sp)
        lw      t1,  8(sp)
        lw      t2, 12(sp)
        lw      a0, 16(sp)
        lw      a1, 20(sp)
        lw      a2, 24(sp)
        lw      a3, 28(sp)
        lw      a4, 32(sp)
        lw      a5, 36(sp)
        lw      a6, 40(sp)
        lw      a7, 44(sp)
        lw      t3, 48(sp)
        lw      t4, 52(sp)
        lw      t5, 56(sp)
        lw      t6, 60(sp)
        addi    sp, sp, 64
        mret

# default handler : any trap is a failure (RESULT = mcause)
        .weak   trap_handler
trap_handler:
        li      t0, 0x40003000
        sw      a0, 4(t0)
        sw      zero, 0(t0)
1:      j       1b
