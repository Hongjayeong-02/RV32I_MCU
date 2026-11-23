/* t05_c : compiled C (gcc -O2) : arrays, loops, function calls, .data/.bss,
 * byte / half accesses, signed compare, multiply and divide through libgcc. */
#include <stdint.h>

static int32_t  arr[16] = { 9, -3, 27, 0, 14, -100, 55, 8, 1, 33, -7, 2, 18, 6, 40, -1 };
static uint8_t  buf[32];
static uint16_t hbuf[8];
static const char msg[] = "RV32I MCU";
volatile int32_t sink;

static void sort(int32_t *a, int n)
{
        for (int i = 0; i < n - 1; i++)
                for (int j = 0; j < n - 1 - i; j++)
                        if (a[j] > a[j + 1]) { int32_t t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }
}

static uint32_t crc8(const uint8_t *p, int n)
{
        uint32_t c = 0;
        for (int i = 0; i < n; i++) {
                c ^= p[i];
                for (int k = 0; k < 8; k++)
                        c = (c & 0x80) ? ((c << 1) ^ 0x07) & 0xff : (c << 1) & 0xff;
        }
        return c;
}

int main(void)
{
        sort(arr, 16);
        for (int i = 0; i < 15; i++)
                if (arr[i] > arr[i + 1]) return 1;
        if (arr[0] != -100 || arr[15] != 55) return 2;

        int n = 0;
        while (msg[n]) { buf[n] = (uint8_t)msg[n]; n++; }
        if (n != 9) return 3;
        if (crc8(buf, n) != crc8((const uint8_t *)msg, n)) return 4;

        for (int i = 0; i < 8; i++) hbuf[i] = (uint16_t)(0xF000 + i * 0x111);
        uint32_t s = 0;
        for (int i = 0; i < 8; i++) s += hbuf[i];
        if (s != 8 * 0xF000 + 0x111 * 28) return 5;

        volatile int32_t a = 1234, b = -56;
        sink = a * b;
        if (sink != -69104) return 6;
        sink = a / 7;
        if (sink != 176) return 7;
        sink = b % 5;
        if (sink != -1) return 8;
        return 0;
}
