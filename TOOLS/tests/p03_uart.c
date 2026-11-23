/* p03_uart : UART V4 inside the MCU (spec 8, 12 T09)  REPLAY-TEST
 *   board : uart_rx = uart_tx (testbench loopback), clk_uart asynchronous
 *   U1 config through the CDC handshake : poll CFG_BUSY before each write
 *   U2 polled TX -> RX, 16 bytes, in order
 *   U3 RX interrupt : handler drains the FIFO into a buffer, 16 bytes
 *   U4 (spec T09) timer interrupts every ~60 cycles while main reads RXDATA
 *      directly. An APB read that has started is never interrupted, so every
 *      byte is popped exactly once : a lost or doubled byte fails the test. */
#include "mcu.h"

#define N 16
static volatile uint8_t rxbuf[48];
static volatile uint32_t rxn, ticks, ticking, bad_cause;

static void uart_cfg(volatile uint32_t *reg, uint32_t v)
{
        while (UART_STATUS & UART_ST_CFGBUSY) ;
        *reg = v;
        while (UART_STATUS & UART_ST_CFGBUSY) ;
}

uint32_t trap_handler(uint32_t cause, uint32_t epc)
{
        if (cause == MCAUSE_MEI) {
                while (UART_STATUS & UART_ST_RXAVAIL) {
                        uint32_t d = UART_RXDATA;
                        if (rxn < sizeof(rxbuf)) rxbuf[rxn] = (uint8_t)d;
                        rxn++;
                }
        } else if (cause == MCAUSE_MTI) {
                ticks++;
                if (ticking) timer_set_cmp(timer_now() + 60);
                else         timer_set_cmp(~0ull);
        } else {
                bad_cause = cause;
                return epc + 4;
        }
        return epc;
}

static uint8_t pat(uint32_t i, uint32_t k) { return (uint8_t)(i * 37 + k * 11 + 5); }

int main(void)
{
        /* U1 */
        uart_cfg(&UART_BAUDDIV, 1);
        uart_cfg(&UART_CTRL, UART_CTRL_EN | UART_CTRL_TXEN | UART_CTRL_RXEN);
        if (UART_BAUDDIV != 1) return 10;
        if ((UART_CTRL & 7) != 7) return 11;

        /* U2 */
        for (uint32_t i = 0; i < N; i++) UART_TXDATA = pat(i, 0);
        for (uint32_t i = 0; i < N; i++) {
                uint32_t spin = 0;
                while (!(UART_STATUS & UART_ST_RXAVAIL)) if (++spin > 20000) return 20;
                if ((uint8_t)UART_RXDATA != pat(i, 0)) return 21;
        }
        if (!(UART_STATUS & UART_ST_RXEMPTY)) return 22;

        /* U3 */
        rxn = 0;
        UART_IRQ_EN = UART_IRQ_RX;
        csr_write(mie, MIE_MEIE);
        csr_set(mstatus, MSTATUS_MIE);
        for (uint32_t i = 0; i < N; i++) UART_TXDATA = pat(i, 1);
        uint32_t spin = 0;
        while (rxn < N && ++spin < 50000) ;
        if (rxn != N) return 30;
        for (uint32_t i = 0; i < N; i++) if (rxbuf[i] != pat(i, 1)) return 31;
        UART_IRQ_EN = 0;

        /* U4 */
        csr_write(mie, MIE_MTIE);
        ticking = 1;
        timer_set_cmp(timer_now() + 60);
        uint32_t got = 0;
        for (uint32_t k = 2; k < 4; k++) {
                for (uint32_t i = 0; i < N; i++) UART_TXDATA = pat(i, k);
                for (uint32_t i = 0; i < N; i++) {
                        spin = 0;
                        while (!(UART_STATUS & UART_ST_RXAVAIL)) if (++spin > 20000) return 40;
                        if ((uint8_t)UART_RXDATA != pat(i, k)) return 41;
                        got++;
                }
        }
        ticking = 0;
        if (got != 2 * N) return 42;
        if (ticks < 10) return 43;              /* the timer really interrupted the loop */
        csr_clear(mstatus, MSTATUS_MIE);
        if (bad_cause) return 50;
        return 0;
}
