/* d01_demo : UART console demo firmware  REPLAY-TEST
 *   board : tb_mcu_demo (host terminal on UART, switches / button on GPIO_IN)
 *           NOT for tb_mcu (its UART loopback would feed the output back in) :
 *           run_mcu.sh skips d* programs
 *   UART 8N1, BAUDDIV 1 ; RX by interrupt into a ring buffer ; timer tick every
 *   TICK cycles ; GPIO_IN[3] rising edge = button interrupt
 *   commands : help | led <hex> | sw | stat | exit   (anything else -> "?")
 *   exit : main returns 0 -> TEST_STATUS = PASS -> o_halt */
#include "mcu.h"

#define TICK    2000u           /* timer period in mtime ticks */
#define RXQ     32u             /* RX ring size (power of 2) */
#define BTN     (1u << 3)

static volatile uint8_t  rxq[RXQ];
static volatile uint32_t rx_wr, rx_rd, ticks, btn, bad;
static uint64_t next_cmp;

uint32_t trap_handler(uint32_t cause, uint32_t epc)
{
        if (cause == MCAUSE_MEI) {
                while (UART_STATUS & UART_ST_RXAVAIL) {
                        uint32_t d = UART_RXDATA;
                        if (rx_wr - rx_rd < RXQ) rxq[rx_wr++ & (RXQ - 1)] = (uint8_t)d;
                }
                uint32_t s = GPIO_IRQ_STATUS;
                if (s) { GPIO_IRQ_STATUS = s; if (s & BTN) btn++; }
        } else if (cause == MCAUSE_MTI) {
                ticks++;
                next_cmp += TICK;
                timer_set_cmp(next_cmp);
        } else {
                bad++;
                return epc + 4;
        }
        return epc;
}

static void uart_cfg(volatile uint32_t *reg, uint32_t v)
{
        while (UART_STATUS & UART_ST_CFGBUSY) ;
        *reg = v;
        while (UART_STATUS & UART_ST_CFGBUSY) ;
}

static void putc_(char c)
{
        while (UART_STATUS & UART_ST_TXFULL) ;
        UART_TXDATA = (uint8_t)c;
}

static void puts_(const char *s) { while (*s) putc_(*s++); }

static void puthex(uint32_t v, int n)
{
        for (int i = (n - 1) * 4; i >= 0; i -= 4)
                putc_("0123456789abcdef"[(v >> i) & 0xF]);
}

static char getc_(void)
{
        while (rx_rd == rx_wr) ;
        return (char)rxq[rx_rd++ & (RXQ - 1)];
}

static int streq(const char *a, const char *b)
{
        while (*a && *a == *b) { a++; b++; }
        return *a == *b;
}

static int parse_hex(const char *s, uint32_t *v)
{
        uint32_t r = 0;
        int n = 0;
        for (; *s; s++, n++) {
                char c = *s;
                if      (c >= '0' && c <= '9') r = (r << 4) | (uint32_t)(c - '0');
                else if (c >= 'a' && c <= 'f') r = (r << 4) | (uint32_t)(c - 'a' + 10);
                else return 0;
        }
        *v = r;
        return n > 0;
}

int main(void)
{
        uart_cfg(&UART_BAUDDIV, 1);
        uart_cfg(&UART_CTRL, UART_CTRL_EN | UART_CTRL_TXEN | UART_CTRL_RXEN);
        UART_IRQ_EN = UART_IRQ_RX;
        GPIO_IRQ_EN = BTN;
        next_cmp = timer_now() + TICK;
        timer_set_cmp(next_cmp);
        csr_write(mie, MIE_MEIE | MIE_MTIE);
        csr_set(mstatus, MSTATUS_MIE);

        puts_("\r\nRV32I MCU demo (UART V4 + 5-stage core)\r\n");
        char line[24];
        for (;;) {
                puts_("> ");
                uint32_t n = 0;
                for (;;) {
                        char c = getc_();
                        if (c == '\r') break;
                        if (n < sizeof(line) - 1) { line[n++] = c; putc_(c); }
                }
                line[n] = 0;
                puts_("\r\n");

                char *arg = line;
                while (*arg && *arg != ' ') arg++;
                if (*arg) *arg++ = 0;

                uint32_t v;
                if (streq(line, "help")) {
                        puts_("help | led <hex> | sw | stat | exit\r\n");
                } else if (streq(line, "led") && parse_hex(arg, &v)) {
                        GPIO_OUT = v & 0xF;
                        puts_("led=");
                        puthex(GPIO_OUT, 1);
                        puts_("\r\n");
                } else if (streq(line, "sw")) {
                        puts_("sw=");
                        puthex(GPIO_IN & 0xF, 1);
                        puts_("\r\n");
                } else if (streq(line, "stat")) {
                        uint32_t cyc = csr_read(mcycle), ins = csr_read(minstret);
                        puts_("cycle=");   puthex(cyc, 8);
                        puts_(" instret="); puthex(ins, 8);
                        puts_(" tick=");   puthex(ticks, 4);
                        puts_(" btn=");    puthex(btn, 2);
                        puts_("\r\n");
                } else if (streq(line, "exit")) {
                        puts_("bye\r\n");
                        while (UART_STATUS & UART_ST_TXBUSY) ;
                        break;
                } else {
                        puts_("?\r\n");
                }
        }
        csr_clear(mstatus, MSTATUS_MIE);
        return bad ? 1 : 0;
}
