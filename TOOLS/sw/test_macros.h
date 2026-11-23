# test_macros.h : helpers for assembly tests
#   PASS / FAIL write TEST_STATUS (halts the TB and the ISS)
#   CHECK rX, value : if rX != value -> FAIL with the line number in TEST_RESULT
#   x30 (t5) / x31 (t6) are scratch for these macros : tests must not use them
#define PASS            li t6, 0x40003000 ; li t5, 1 ; sw t5, 0(t6) ; 9: j 9b
#define CHECK(r, v)     li t5, v ; beq r, t5, 1f ; li t6, 0x40003000 ; li t5, __LINE__ ; sw t5, 4(t6) ; sw zero, 0(t6) ; 8: j 8b ; 1:
