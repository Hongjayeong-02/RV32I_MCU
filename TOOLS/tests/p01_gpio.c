/* p01_gpio : GPIO data path and edge interrupts (spec 8)  REPLAY-TEST
 *   board : gpio_in = gpio_out (testbench loopback)
 *   G1 every output pattern reads back on DATA_IN after the 2-FF sync
 *   G2 a rising edge sets IRQ_STATUS even with IRQ_EN = 0 ; W1C clears it
 *   G3 rising edge with IRQ_EN + MEIE -> interrupt, handler W1C, one per edge
 *   G4 falling edges and an IRQ_EN-disabled bit do not interrupt */
#include "mcu.h"

static volatile uint32_t irq_cnt, irq_bits, bad_cause;

uint32_t trap_handler(uint32_t cause, uint32_t epc)
{
        if (cause != MCAUSE_MEI) { bad_cause = cause; return epc + 4; }
        uint32_t s = GPIO_IRQ_STATUS;
        GPIO_IRQ_STATUS = s;                    /* W1C */
        irq_bits |= s;
        irq_cnt++;
        return epc;
}

static void settle(void) { for (volatile int i = 0; i < 3; i++) ; }

int main(void)
{
        /* G1 */
        for (uint32_t v = 0; v < 16; v++) {
                GPIO_OUT = v;
                settle();
                if (GPIO_OUT != v)  return 10;
                if (GPIO_IN  != v)  return 11;
        }
        /* G2 : last pattern was 15 ; go 0 -> 5 : rising on bits 0 and 2 */
        GPIO_OUT = 0; settle();
        GPIO_IRQ_STATUS = 0xF;
        if (GPIO_IRQ_STATUS != 0) return 20;
        GPIO_OUT = 5; settle();
        if (GPIO_IRQ_STATUS != 5) return 21;
        GPIO_IRQ_STATUS = 1;
        if (GPIO_IRQ_STATUS != 4) return 22;
        GPIO_IRQ_STATUS = 4;
        if (GPIO_IRQ_STATUS != 0) return 23;

        /* G3 */
        GPIO_OUT = 0; settle();
        GPIO_IRQ_STATUS = 0xF;
        GPIO_IRQ_EN = 0x7;                      /* bit 3 disabled */
        csr_write(mie, MIE_MEIE);
        csr_set(mstatus, MSTATUS_MIE);
        GPIO_OUT = 1; settle();
        GPIO_OUT = 3; settle();
        GPIO_OUT = 7; settle();
        if (irq_cnt != 3 || irq_bits != 7) return 30;
        /* G4 : falling edges, and a rising edge on the disabled bit 3 */
        GPIO_OUT = 0; settle();
        GPIO_OUT = 8; settle();
        if (irq_cnt != 3) return 40;
        if (GPIO_IRQ_STATUS != 8) return 41;    /* recorded but not enabled */
        GPIO_IRQ_STATUS = 8;
        csr_clear(mstatus, MSTATUS_MIE);
        if (bad_cause) return 50;
        return 0;
}
