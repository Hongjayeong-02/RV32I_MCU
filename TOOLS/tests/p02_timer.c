/* p02_timer : mtime / mtimecmp and the machine timer interrupt (spec 8)  REPLAY-TEST
 *   M1 MTIME counts up ; CTRL[0] = 0 stops it
 *   M2 after reset MTIMECMP = all ones -> no interrupt
 *   M3 one-shot : cmp = now + 300 -> exactly one MTI, mtime >= cmp in the handler
 *   M4 periodic : handler re-arms +150, five interrupts, main loop keeps running
 *   M5 64-bit compare : cmp in the upper half -> no interrupt */
#include "mcu.h"

static volatile uint32_t ticks, late, bad_cause, periodic;
static volatile uint64_t cmp_shadow;

uint32_t trap_handler(uint32_t cause, uint32_t epc)
{
        if (cause != MCAUSE_MTI) { bad_cause = cause; return epc + 4; }
        if (timer_now() < cmp_shadow) late = 1;
        ticks++;
        if (periodic && ticks < 5) { cmp_shadow += 150; timer_set_cmp(cmp_shadow); }
        else                       { cmp_shadow = ~0ull; timer_set_cmp(~0ull); }
        return epc;
}

int main(void)
{
        /* M1 */
        uint32_t a = MTIME_LO, b = MTIME_LO;
        if (b <= a) return 10;
        TIMER_CTRL = 0;
        a = MTIME_LO; b = MTIME_LO;
        if (a != b) return 11;
        TIMER_CTRL = 1;
        if (MTIMECMP_LO != 0xFFFFFFFFu || MTIMECMP_HI != 0xFFFFFFFFu) return 12;

        /* M2 */
        csr_write(mie, MIE_MTIE);
        csr_set(mstatus, MSTATUS_MIE);
        for (volatile int i = 0; i < 20; i++) ;
        if (ticks != 0) return 20;

        /* M3 */
        cmp_shadow = timer_now() + 300;
        timer_set_cmp(cmp_shadow);
        uint32_t spin = 0;
        while (ticks == 0 && ++spin < 10000) ;
        if (ticks != 1) return 30;
        if (late) return 31;
        for (volatile int i = 0; i < 50; i++) ;
        if (ticks != 1) return 32;

        /* M4 */
        periodic = 1; ticks = 0;
        cmp_shadow = timer_now() + 150;
        timer_set_cmp(cmp_shadow);
        uint32_t work = 0;
        spin = 0;
        while (ticks < 5 && ++spin < 20000) work += 3;
        if (ticks != 5 || late) return 40;
        if (work == 0) return 41;
        periodic = 0;

        /* M5 */
        timer_set_cmp(timer_now() + (1ull << 32));
        for (volatile int i = 0; i < 50; i++) ;
        if (ticks != 5) return 50;
        csr_clear(mstatus, MSTATUS_MIE);
        if (bad_cause) return 60;
        return 0;
}
