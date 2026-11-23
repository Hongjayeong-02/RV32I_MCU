# crt0.S : reset entry for C programs (spec 9)
#   sp <- RAM top, mtvec <- trap_entry, copy .data ROM->RAM, clear .bss, call main,
#   then TEST_STATUS <- (main() == 0) ; RESULT <- main() return value
        .section .text.init
        .globl  _start
_start:
        li      sp, 0x10000400          # __stack_top
        la      t0, trap_entry          # sw/trap.S
        csrw    mtvec, t0
        la      t0, __data_load
        la      t1, __data_start
        la      t2, __data_end
1:      bgeu    t1, t2, 2f
        lw      t3, 0(t0)
        sw      t3, 0(t1)
        addi    t0, t0, 4
        addi    t1, t1, 4
        j       1b
2:      la      t1, __bss_start
        la      t2, __bss_end
3:      bgeu    t1, t2, 4f
        sw      zero, 0(t1)
        addi    t1, t1, 4
        j       3b
4:      call    main
        li      t0, 0x40003000
        sw      a0, 4(t0)               # TEST_RESULT = return value
        seqz    a0, a0
        sw      a0, 0(t0)               # TEST_STATUS : 1 = PASS (main returned 0)
5:      j       5b
