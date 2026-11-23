/* mcu.h : RV32I MCU register map (spec 7, 8) */
#ifndef MCU_H
#define MCU_H
#include <stdint.h>

#define REG32(a)        (*(volatile uint32_t *)(a))

/* UART V4 */
#define UART_BASE       0x40000000u
#define UART_TXDATA     REG32(UART_BASE + 0x00)
#define UART_RXDATA     REG32(UART_BASE + 0x04)
#define UART_STATUS     REG32(UART_BASE + 0x08)
#define UART_CTRL       REG32(UART_BASE + 0x0C)
#define UART_BAUDDIV    REG32(UART_BASE + 0x10)
#define UART_IRQ_EN     REG32(UART_BASE + 0x14)
#define UART_IRQ_STATUS REG32(UART_BASE + 0x18)
#define UART_FIFO_LEVEL REG32(UART_BASE + 0x1C)
#define UART_ST_TXEMPTY (1u << 0)
#define UART_ST_TXFULL  (1u << 1)
#define UART_ST_RXEMPTY (1u << 2)
#define UART_ST_RXFULL  (1u << 3)
#define UART_ST_TXBUSY  (1u << 4)
#define UART_ST_RXAVAIL (1u << 5)
#define UART_ST_CFGBUSY (1u << 9)
#define UART_CTRL_EN    (1u << 0)
#define UART_CTRL_TXEN  (1u << 1)
#define UART_CTRL_RXEN  (1u << 2)
#define UART_IRQ_RX     (1u << 0)

/* GPIO */
#define GPIO_BASE       0x40001000u
#define GPIO_IN         REG32(GPIO_BASE + 0x00)
#define GPIO_OUT        REG32(GPIO_BASE + 0x04)
#define GPIO_IRQ_EN     REG32(GPIO_BASE + 0x08)
#define GPIO_IRQ_STATUS REG32(GPIO_BASE + 0x0C)

/* TIMER */
#define TIMER_BASE      0x40002000u
#define MTIME_LO        REG32(TIMER_BASE + 0x00)
#define MTIME_HI        REG32(TIMER_BASE + 0x04)
#define MTIMECMP_LO     REG32(TIMER_BASE + 0x08)
#define MTIMECMP_HI     REG32(TIMER_BASE + 0x0C)
#define TIMER_CTRL      REG32(TIMER_BASE + 0x10)

/* TEST */
#define TEST_BASE       0x40003000u
#define TEST_STATUS     REG32(TEST_BASE + 0x00)
#define TEST_RESULT     REG32(TEST_BASE + 0x04)
#define TEST_IRQ        REG32(TEST_BASE + 0x08)

/* CSR helpers */
#define csr_read(c)     ({ uint32_t _v; __asm__ volatile ("csrr %0, " #c : "=r"(_v)); _v; })
#define csr_write(c, v) __asm__ volatile ("csrw " #c ", %0" :: "r"(v))
#define csr_set(c, v)   __asm__ volatile ("csrs " #c ", %0" :: "r"(v))
#define csr_clear(c, v) __asm__ volatile ("csrc " #c ", %0" :: "r"(v))
#define MSTATUS_MIE     (1u << 3)
#define MIE_MTIE        (1u << 7)
#define MIE_MEIE        (1u << 11)
#define MCAUSE_MTI      0x80000007u
#define MCAUSE_MEI      0x8000000Bu

/* 64-bit mtimecmp write without a false interrupt (spec 8) */
static inline void timer_set_cmp(uint64_t t)
{
        MTIMECMP_LO = 0xFFFFFFFFu;
        MTIMECMP_HI = (uint32_t)(t >> 32);
        MTIMECMP_LO = (uint32_t)t;
}

static inline uint64_t timer_now(void)
{
        uint32_t hi, lo;
        do { hi = MTIME_HI; lo = MTIME_LO; } while (hi != MTIME_HI);
        return ((uint64_t)hi << 32) | lo;
}

/* called from sw/trap.S with mcause / mepc ; may return a new mepc */
uint32_t trap_handler(uint32_t cause, uint32_t epc);

#endif
