// riscv_test.h : riscv-tests environment for the RV32I MCU memory map
//   (replaces riscv-test-env/p/riscv_test.h ; encoding.h is copied unchanged
//    from riscv-test-env, BSD license)
//   - code in ROM 0x0, .data copied ROM -> RAM 0x1000_0000 at reset
//   - pass / fail are written to the TEST device instead of tohost:
//       PASS : TEST_STATUS = 1
//       FAIL : TEST_RESULT = TESTNUM (test case << 1 | 1), TEST_STATUS = 0
//   - machine mode only : mret to the test body keeps M-mode (MPP = 11)
#ifndef _ENV_RV32I_MCU_H
#define _ENV_RV32I_MCU_H

#include "encoding.h"

#define RVTEST_RV32U    .macro init; .endm
#define RVTEST_RV64U    .macro init; .endm
#define RVTEST_RV32M    .macro init; li a0, MSTATUS_MPP; csrs mstatus, a0; .endm
#define RVTEST_RV64M    RVTEST_RV32M

#define TESTNUM gp
#define MCU_TEST_BASE 0x40003000

#define INIT_XREG                                                       \
  li x1, 0;  li x2, 0;  li x3, 0;  li x4, 0;  li x5, 0;  li x6, 0;     \
  li x7, 0;  li x8, 0;  li x9, 0;  li x10, 0; li x11, 0; li x12, 0;    \
  li x13, 0; li x14, 0; li x15, 0; li x16, 0; li x17, 0; li x18, 0;    \
  li x19, 0; li x20, 0; li x21, 0; li x22, 0; li x23, 0; li x24, 0;    \
  li x25, 0; li x26, 0; li x27, 0; li x28, 0; li x29, 0; li x30, 0;    \
  li x31, 0;

#define INTERRUPT_HANDLER j other_exception

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  2;                                                      \
        .weak mtvec_handler;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        j reset_vector;                                                 \
        .align 2;                                                       \
trap_vector:                                                            \
        csrr t5, mcause;                                                \
        li t6, CAUSE_MACHINE_ECALL;                                     \
        beq t5, t6, write_tohost;                                       \
        la t5, mtvec_handler;                                           \
        beqz t5, 1f;                                                    \
        jr t5;                                                          \
  1:    csrr t5, mcause;                                                \
        bgez t5, handle_exception;                                      \
        INTERRUPT_HANDLER;                                              \
handle_exception:                                                       \
  other_exception:                                                      \
        ori TESTNUM, TESTNUM, 1337;                                     \
  write_tohost:                                                         \
        li t5, MCU_TEST_BASE;                                           \
        li t6, 1;                                                       \
        beq TESTNUM, t6, 2f;                                            \
        sw TESTNUM, 4(t5);                                              \
        sw zero, 0(t5);                                                 \
  3:    j 3b;                                                           \
  2:    sw t6, 0(t5);                                                   \
        j 3b;                                                           \
reset_vector:                                                           \
        INIT_XREG;                                                      \
        li TESTNUM, 0;                                                  \
        la t0, trap_vector;                                             \
        csrw mtvec, t0;                                                 \
        la t0, __data_load;                                             \
        la t1, __data_start;                                            \
        la t2, __data_end;                                              \
  4:    bgeu t1, t2, 5f;                                                \
        lw t3, 0(t0);                                                   \
        sw t3, 0(t1);                                                   \
        addi t0, t0, 4;                                                 \
        addi t1, t1, 4;                                                 \
        j 4b;                                                           \
  5:    li t0, 0; li t1, 0; li t2, 0; li t3, 0;                         \
        csrwi mstatus, 0;                                               \
        init;                                                           \
        la t0, 1f;                                                      \
        csrw mepc, t0;                                                  \
        csrr a0, mhartid;                                               \
        mret;                                                           \
        .section .text;                                                 \
1:

#define RVTEST_CODE_END unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        li a7, 93;                                                      \
        li a0, 0;                                                       \
        ecall

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        li a7, 93;                                                      \
        addi a0, TESTNUM, 0;                                            \
        ecall

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
