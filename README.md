# PROJ2 : RV32I MCU — RTL to GDS

직접 설계한 RV32I 5단 파이프라인 CPU + UART V4 + GPIO / Timer / TEST 를 묶은 MCU (목표 약 3만 instance).
설계 사양 : Claude Docs "UART V4 MCU (RV32I) 설계 사양서" Rev 1.2. 폴더 구조는 PROJ1 과 같다.

```
PROJ2/
├── proj2_make/TOP/
│   ├── RTL/MCU_V1/           RTL (rv32_* = CPU, mcu_* = SoC, mcu_chip_top = PAD 14 개 + mcu_top), uart_v4/ = UART 레포 고정 복사 (SOURCE.md)
│   ├── SIM/
│   │   ├── sim_env.sh        경로 · 파일 목록 (세 스크립트 공용)
│   │   ├── TESTBENCH/        tb_rv32_* (모듈), tb_rv32_core (코어), tb_mcu (SoC)
│   │   ├── PROG/<test>/      rv32_rom.v · expected.hex/.trace (ISS) · rom.bin · prog.dump
│   │   ├── FUNCTION/         run_m1.sh  : leaf 모듈 7 개
│   │   ├── REGRESS/          run_core.sh : 코어 126 run / run_mcu.sh : SoC 66 개
│   │   └── GLS/              run_gls.sh : post-route GLS (P&R netlist + SDF, SS/FF), "chip" 인자 = 칩 레벨 (PAD 모델)
│   ├── SYN/
│   │   ├── cons/             mcu_top_10ns.sdc, mcu_chip_top_10ns.sdc (M5), rv32_ram_10ns.sdc
│   │   ├── script/           run_syn_mcu_10ns.tcl (M4), run_syn_chip_10ns.tcl (M5, PAD lib), run_ram_sweep.csh (M0)
│   │   └── report_*/         결과
│   ├── APR/
│   │   ├── scripts/          블록 (M4) : Innovus 0~5 단계 (UART V4 흐름), 6_EcoDrc.tcl, make_pdk_setup.sh
│   │   └── scripts_chip/     칩 (M5) : PAD ring (mcu_chip.io, respace_chip.tcl), 0~5 단계, stream_pdkmap_chip.tcl
│   ├── LEC/                  make_lec_pkg.sh (블록), make_lec_pkg_chip.sh (칩) : Conformal 서버로 옮길 LEC 패키지
│   └── MERGE/                칩 GDS merge (M5-5) : mcu_logo.il, mcu_final.il (SEALRING · LOGO · 최종 셀)
└── TOOLS/                    서버 밖에서 실행 (RISC-V gcc, python3)
    ├── rv32_iss.py           golden model (commit trace)
    ├── check_replay.py       SoC 주변장치 테스트 검사 (RTL 인터럽트 시점 · MMIO 값만 받아 ISS 재실행)
    ├── build_prog.py         tests/ → SIM/PROG/ (+ --riscv-tests)
    ├── tests/ sw/            테스트 프로그램, crt0 · trap · link.ld · mcu.h
    └── riscv_tests_env/      riscv-tests 를 이 메모리 맵에서 돌리는 env
```

## 실행 (서버, Xcelium · Genus)
```
cd proj2_make/TOP/SIM/FUNCTION ; bash run_m1.sh              # leaf 모듈
cd proj2_make/TOP/SIM/REGRESS  ; bash run_core.sh [quick]    # 코어 (wait 0/1)
cd proj2_make/TOP/SIM/REGRESS  ; bash run_mcu.sh  [quick]    # SoC
cd proj2_make/TOP/SYN          ; genus -files script/run_syn_mcu_10ns.tcl -log log/syn_mcu_10ns
cd proj2_make/TOP/APR/scripts  ; bash make_pdk_setup.sh       # 1 회 : UART V4 스크립트에서 PDK 경로 추출
cd proj2_make/TOP/APR/work     ; innovus -files ../scripts/run_all.tcl -log ../log/apr_u60
cd proj2_make/TOP/APR/work     ; innovus -files ../scripts/6_EcoDrc.tcl -log ../log/eco_drc   # 남은 route DRC 수정
cd proj2_make/TOP/LEC          ; bash make_lec_pkg.sh         # → Conformal 서버에서 TOP/SYN/rtl2gate_pkg.do, syn2pnr.do
cd proj2_make/TOP/SIM/GLS      ; bash run_gls.sh prep ; bash run_gls.sh run   # 결과 gls_results.txt
# M5 칩 레벨
cd proj2_make/TOP/SIM/REGRESS  ; bash run_mcu.sh quick chip   # PAD 우회 RTL, mcu_top 과 trace 동일해야 함
cd proj2_make/TOP/SYN          ; genus -files script/run_syn_chip_10ns.tcl -log log/syn_chip_10ns
cd proj2_make/TOP/APR/scripts_chip ; bash make_pdk_setup_chip.sh   # 1 회 : UART V3 PADALL 스크립트에서 PDK 경로 추출
cd proj2_make/TOP/APR/work_chip    ; innovus -files ../scripts_chip/run_all_chip.tcl -log ../log/apr_chip
cd proj2_make/TOP/LEC          ; bash make_lec_pkg_chip.sh
cd proj2_make/TOP/SIM/GLS      ; bash run_gls.sh prep chip ; bash run_gls.sh run chip   # 결과 chip/gls_results.txt
# 데모 (UART 콘솔 펌웨어 d01_demo, tb_mcu_demo 가 터미널)
cd proj2_make/TOP/SIM/REGRESS  ; bash run_demo.sh ; bash run_demo.sh chip   # 콘솔 = PROG/d01_demo/console.golden
setenv MCU_PROG d01_demo   # (tcsh) 합성 · LEC 패키지가 이 ROM 을 쓴다. 기존 칩 결과는 먼저 다른 이름으로 옮겨 둘 것
cd proj2_make/TOP/SIM/GLS      ; bash run_gls.sh prep chip demo ; bash run_gls.sh run chip demo   # 결과 chip/gls_demo_results.txt
# GDS : Innovus 에서 source ../scripts_chip/stream_pdkmap_chip.tcl → Virtuoso Stream In 3 회
#       (design → 표준셀 → IO) → CIW load "MERGE/mcu_final.il" → Stream Out → PVS DRC
```
서버에 python3 가 없으면 주변장치 테스트 (p*) 는 trace / event 파일을 `PROG/<t>/replay.md5` 와 비교한다
(replay PASS 를 확인한 실행과 바이트가 같으면 MD5OK).

## 진행 상황
| 단계 | 내용 | 상태 |
|---|---|---|
| M0 | RAM 단독 합성 sweep → 1 KB (15,226 inst, slack +2.458 ns @10 ns) | 완료 |
| M1 | leaf 모듈 + 5단 파이프라인, ISS commit trace 비교 | Xcelium PASS |
| M2 | CSR · 예외 · 인터럽트 · mret, riscv-tests 52 개 | Xcelium 124 run PASS |
| M3 | mcu_top : dbus · APB 브리지 · GPIO · Timer · TEST · UART V4 | Xcelium 65 PASS (p* replay MD5OK) |
| M4 | 합성 v2 : 27,361 inst (seq 10,857), slack +1.824 ns @10 ns (forwarding 사전 계산으로 +0.602 ns) | 완료 |
| M4 | LEC RTL ↔ 합성 (Genus 가 쓴 fv flow, 계층 비교) | PASS |
| M4 | P&R v2 : DRC 0 · connectivity 0, setup +1.553 / hold +0.005 ns, density 약 65 % | 완료 |
| M4 | LEC 합성 ↔ P&R : DFF 10,857 + PO 6 Equivalent | PASS |
| M4 | post-route GLS (p03_uart, SS max / FF min SDF) : halt@41501 = RTL, SDF 에러 0, 타이밍 위반 0 | PASS |
| M5-1 | mcu_chip_top (PADDI 8 · PADDO 6), PAD 우회 RTL 13 개 : trace · event 가 mcu_top 과 바이트 단위 동일 | PASS |
| M5-2 | 칩 합성 : 27,284 inst (seq 10,857), PAD 14 preserve, slack +1.717 ns, 출력 PAD 경로 +4.661 ns | 완료 |
| M5-3 | 칩 P&R v2 : die 1000 × 1000 µm, PAD 22 + corner 4, density 약 52 %, 신호 배선 Metal5 까지, DRC 0, setup +1.174 / hold +0.009 ns (I/O +4.099 / +0.323) | 완료 (PAD ring 전원 connectivity info 12 → 아래) |
| M5-4 | LEC RTL ↔ 칩 합성 (계층, 24 모듈 EQ) · 칩 합성 ↔ 칩 P&R v2 (DFF 10,857 + PO 6 EQ) | PASS |
| M5-4 | 칩 GLS v2 (p03_uart, PAD 모델, SS / FF) : halt@41501 = RTL, SDF 에러 0 / SDFINF 0, 위반은 CDC 동기화기 1단 4 건뿐 | PASS |
| M5-5 | GDS merge (Virtuoso, Stream In 3 회 0 error) + SEALRING · LOGO → 최종 칩 1020 × 1020 µm, Stream Out 0 error | 완료 |
| M5-5 | PVS DRC (UART V3 와 같은 rule deck) : v1 1,254 건 → v2 1,131 건, 남은 것은 PAD ring Metal4 와 기판 soft check 뿐 (아래) | 완료 |
| TB | mutation 21 종 (RTL 버그 주입) : 미검출 6 종 분석 → 실제 빈틈 1 종 (인터럽트에 걸린 csrw minstret 이 카운터를 써 버림) 은 t11_irq_csr 추가로 검출, 5 종은 중복 로직이라 등가 (아래) | 16 / 16 검출 |
| 데모 | UART 콘솔 펌웨어 (d01_demo) 로 칩 합성 · P&R · LEC · GLS 다시 수행 (아래 "데모 칩") | RTL · LEC · GLS SS PASS, GLS FF 미실시 |

검증 범위 : 게이트 레벨은 펌웨어 1 개 (p03_uart : UART 루프백 · 인터럽트 · 타이머) 만 실행했다.
나머지 65 개 테스트는 RTL 결과다. ROM 이 netlist 안에 합성되므로 펌웨어를 바꾸면 합성 · P&R 을 다시 해야 한다.
I/O 타이밍과 PAD 는 M5 에서 칩 SDC (출력 PAD 경로 40 % budget) 와 칩 GLS 로 확인했다. LVS 는 하지 않았다
(UART V3 에서 IO 라이브러리 LEF ↔ GDS PAD 핀 80 µm 불일치와 IO bulk 모델링으로 미통과, 같은 IO 라이브러리).

## TB 신뢰성 : mutation

RTL 에 버그를 하나씩 넣고 코어 TB (wait 0/1) · SoC TB 가 FAIL 하는지 본다. 21 종 중 15 종 검출, 6 종 미검출.

| 미검출 변형 | 판정 | 근거 |
|---|---|---|
| trap 이 걸린 CSR 명령도 CSR 을 씀 | **실제 빈틈** | mscratch 등은 trap 분기가 먼저라 막히지만 minstret / mcycle 은 따로 쓰는 블록이라 그대로 써짐. 기존 테스트에는 인터럽트가 카운터 쓰기에 걸리는 경우가 없었음 → `t11_irq_csr` 추가 후 검출 |
| EX/MEM 이 MEM/WB 보다 우선하지 않음 | 등가 | EX 의 operand mux 가 selEx 를 먼저 보므로 selWb 의 `~selEx` 는 중복 |
| x0 도 forwarding | 등가 | decoder 가 regWrite 를 이미 rd ≠ 0 으로 막음 |
| load / CSR 결과를 EX/MEM 에서 forwarding | 등가 | 같은 조건이면 load-use stall 이 먼저 걸려 ID/EX 가 bubble 이 되고, 다음 사이클 선택은 다시 계산됨 |
| bubble 에서 selEx 를 안 지움 | 등가 | bubble 은 valid 0 · regWrite 0 · branch 0 이라 operand 값이 어디에도 쓰이지 않음 |
| misaligned jump 도 redirect | 등가 (구조적) | 다음 사이클 MEM 의 예외가 IF/ID/EX 를 모두 flush 하고 mtvec 로 감. 차이는 버려질 fetch 주소뿐 |

등가 판정은 RTL 을 읽고 내린 것이고 형식 검증으로 증명한 것은 아니다.

## M4 에서 생긴 문제와 결정
| 문제 | 원인 | 조치 |
|---|---|---|
| LEC RTL ↔ 합성 : 단순 flat 비교에서 non-equivalent 9,464 점 | boundary optimization · 순차 상수 제거로 키 포인트 대응이 깨짐 | Genus 가 쓰는 LEC dofile (fv_map, 계층 비교) 사용 → PASS |
| LEC : `pc[1]` not-mapped | Genus 가 PC[1] 을 순차 상수로 제거 (RTL 에선 늘 0 이지만 코드에 안 드러남) | RTL 에서 PC[1:0] = 0 을 명시 (`{..[31:2], 2'b00}`) → 재합성 · 재 P&R |
| P&R 후 Metal1 spacing DRC 1 개 (u_rom) | ecoRoute -fix_drc 로 안 풀림 | 해당 net 2 개 editDelete 후 ecoRoute (6_EcoDrc.tcl) → DRC 0 |
| GLS 첫 실행 FAIL (SDF 에러 0, 위반 0 인데 halt 안 됨) | `saveNetlist -flat` 이름 (`\u_uart/g2717`) 과 `write_sdf` 계층 이름 (`u_uart/g2717`) 불일치 → 블록 안 셀 지연 · 체크가 통째로 빠져 APB 쓰기가 사라지는 race | 계층 netlist (`mcu_top_pnr_hier.v`) 로 GLS, 결과표에 SDFINF 개수 표시 (0 이어야 함). flat netlist 는 LEC 용 |
| GLS Annotation 경고 2,377 개 | `-recrem split` 의 REMOVAL 체크가 셀 모델에 없음 | 개수 확인 : RN flop 2,291 + SN flop 86 = 2,377 → 전부 리셋 해제 체크, 무해 (STA 에서 확인) |

원인 추적 방법 (GLS) : RTL · SDF 없는 GLS · SDF 있는 GLS 에 같은 probe (리셋, PC) 를 걸어
처음 갈라지는 지점을 찾고, 펌웨어 디스어셈블리로 그 지점의 검사 (BAUDDIV 읽기) 를 확인했다.

## M5 (칩 레벨) 결과와 판단

**블록 vs 칩.** UART V3 PAD 칩은 PAD 82 개가 die 를 정했고 (pad-limited, 1.9 mm, density 0.2 %),
MCU 칩은 PAD 22 개에 코어가 die 를 정한다 (core-limited, 1 mm, density 약 52 %).

| 항목 | 내용 | 판단 |
|---|---|---|
| 칩 P&R connectivity info 12 | PAD 행 안 VDD/VSS 레일 조각 6, corner VDD/VSS 핀 4, VDDIOR/VSSIOR no routing 2 | corner LEF 가 두 변 핀을 별도 PORT 로 두고 L 자 금속은 OBS 라 Innovus 가 못 따라감 (V3 §7.8 과 같음). merge 한 GDS 에서 corner 안 IO ring 금속이 L 자로 이어진 것 확인 → 도구상 판정 |
| setup WNS +1.553 (블록) → +0.772 (칩 v1) → +1.174 (칩 v2) | 같은 로직, 위반 0 | v1 은 density 가 낮아 배선이 길어진 영향으로 추정, v2 는 6 층 via 기둥이 사라지며 개선된 것으로 추정. critical path 비교는 하지 않음 |
| 칩 LEC 1 : `rv32_imm_gen` 단독 NEQ | 경계 최적화로 출력 일부가 상수 → 상위 `rv32_core` 에서 dynamic flattening 후 EQ | M4 와 같음, PASS |
| 칩 GLS 타이밍 위반 4 (SS) | `u_rxFifo.r_wGraySync1_reg[1]` 3, `r_doneSync1_reg[0]` 1 : 두 클럭 edge 가 같은 시각 | Gray 포인터 동기화기 1단, 설계상 허용 (2단이 거름). 다른 위반 0 |
| 칩 GLS 경고 | REMOVAL 2,377 (M4 와 같음), FF corner 입력 PAD `PAD→Y` 음수 지연 → 0 처리 6, `u_bridge` 미연결 출력 포트 1 (P&R 버퍼 포트) | 무해 (칩 LEC PASS) |
| GDS map | Innovus `streamOut` 에 PDK Innovus map 지정 (`stream_pdkmap_chip.tcl`) | V3 에서 map 없이 Metal 이 Via 층으로 들어간 문제 회피 |
| Stream In 대상 라이브러리 | 1 차 시도에서 3 회 모두 V3 라이브러리로 들어감 (GUI Library 칸이 이전 값 유지) | 들어간 셀 1 개 삭제 후 재실행. `mcu_final.il` 이 라이브러리별 셀 존재를 먼저 출력하도록 함 |
| SEALRING 크기 | `mcu_chip_top~>bBox` 가 80 ~ 920 (자기 도형만, PAD · 표준셀 · die 경계 제외) | 배치한 인스턴스 bBox 기준으로 수정. 칩 왼쪽 끝 9.995 는 IO GDS PAD 금속의 −0.005 µm (V3 §7.7 기록과 같음) |

**PVS DRC (최종 셀 `mcu_chip_final`, SEALRING · LOGO 포함)**

| rule | 칩 v1 | 칩 v2 | UART V3 | 판단 |
|---|---|---|---|---|
| VIAk.X.3 / X.4 (4 종) | 122 | **0** | 0 | 6 층 이상 single-cut via 기둥 금지 (Metal1→6 ~ Metal4→9). rule 이 LEF 에 없어 NanoRoute 가 모름. v1 은 122 건 전부 코어 신호 배선 → v2 에서 `setDesignMode -topRoutingLayer Metal5` (Metal6~9 는 전원망 전용) 로 해결 |
| METAL3.SP.1.6 | 1 | **0** | 0 | 위쪽 PAD 행 경계의 넓은 Metal3 간격, v2 재배선에서 사라짐 |
| METAL4.SP.1.6 | 124 | 124 | 276 | PAD ring (PAD 라이브러리), PAD 수 감소로 줄어듦 |
| METAL4.W.2 | 6 | 6 | 454 | 위와 같음 |
| soft_check_4 | 1,000 (상한) | 1,000 (상한) | 95 | "ptap causing multiple stamped connections to psubstrate" : 칩 전체가 p 기판 하나인데 코어 ptap 은 VSS, IO ptap 은 VSSIOR. deck 에 기판 분리 규칙이 없어 ptap 수에 비례해 나옴 (v1 위치 : 코어 640 · PAD 360). V3 §7.7 의 IO bulk 문제와 같은 원인, 라이브러리 · deck 한계 |
| soft_check_5 | 1 | 1 | 1 | V3 와 같음 |
| LOGO · SEALRING | 0 | 0 | 0 | |

위치 분류 방법 : `-ascii` 결과 DB 의 다각형 첫 꼭짓점을 µm 로 바꿔 코어 (280~740) · core ring 채널 · PAD ring 으로 셌다.
V3 의 DRC 는 칩 본체 (`uart_chip_top_allpad`) 를 top 으로 돌렸고, MCU 는 SEALRING · LOGO 를 감싼 최종 셀로 돌렸다.
PVS 실행 주의 : 서버의 `pvs` 는 시스템 LVM 명령이 먼저 잡힌다 → PVS 설치 경로의 `bin/pvs` 를 직접 쓰고,
Innovus 용 `OA_HOME` 이 잡혀 있으면 `env -u OA_HOME` 으로 뺀다.

## 데모 칩 (UART 콘솔 펌웨어)

`TOOLS/tests/d01_demo.c` : UART 로 명령 (`help` · `led <hex>` · `sw` · `stat` · `exit`) 을 받아 답하는 펌웨어.
RX 는 인터럽트로 ring buffer 에 받고, 타이머 인터럽트로 tick 을 세고, GPIO_IN[3] 상승 에지를 버튼 인터럽트로 받는다.
`SIM/TESTBENCH/tb_mcu_demo.v` 가 보드 역할 : host 터미널 (8N1, bit = 16 × (BAUDDIV+1) clk_uart 를 세서 정확히 맞춤),
스위치 5 고정, `stat` 직전 버튼 1 회. 받은 글자를 콘솔 파일로 쓰고 골든과 바이트 단위로 비교 (D4).
기존 `tb_mcu` 는 UART 가 루프백이라 이 펌웨어를 돌릴 수 없어 `run_mcu.sh` 는 `d*` 를 건너뛴다.

```
RV32I MCU demo (UART V4 + 5-stage core)
> help
help | led <hex> | sw | stat | exit
> led a
led=a
> sw
sw=5
> hello
?
> stat
cycle=0001352f instret=000084cb tick=0031 btn=01
> exit
bye
```

ROM 이 netlist 안에 합성되므로 펌웨어를 바꾸면 칩 flow 전체를 다시 돈다 (칩 v2 결과는 `*_v2p03` 으로 보관).

| 단계 | 칩 v2 (p03_uart) | 데모 칩 (d01_demo) |
|---|---|---|
| ROM | 1,372 B | 2,680 B (670 word) |
| 합성 | 27,284 inst · seq 10,857 · slack +1.717 ns | 29,470 inst · seq 10,861 · slack +1.747 ns |
| P&R (setup / hold) | +1.174 / +0.009 ns · DRC 0 | **+0.426** / +0.006 ns · DRC 0 · route 54 분 |
| LEC | RTL↔합성 PASS · 합성↔P&R 10,863 EQ | RTL↔합성 PASS (24 모듈) · 합성↔P&R 10,867 EQ |
| GLS SS (max SDF) | halt@41501 = RTL | 콘솔 199 B = RTL 골든 · halt@126885 = RTL · SDFINF 0 · 위반 3 (Gray sync 1 단) |
| GLS FF (min SDF) | PASS | **미실시** (아래) |

- **setup 여유 감소 원인** : critical path 가 `r_exmemAddr` → ROM 데이터 포트 → `r_memwbData`.
  펌웨어가 `.rodata` 문자열 · hex 표를 `lb` 로 ROM 에서 읽는 MEM 단계 경로이고, ROM 이 670 word 로 커져 case mux 가 깊어졌다.
  실제 칩이라면 ROM 매크로나 레지스터 출력 동기 ROM 을 쓸 자리.
- **seq +4** : p03 ROM 에서 늘 상수였던 명령어 비트를 받는 flop 을 Genus 가 지웠다가, 데모 ROM 에선 비트가 바뀌어 남은 것으로 본다 (추정). LEC 의 DFF 수 변화와 일치.
- **TB race (고친 것)** : 처음 TB 는 clock posedge 직후 blocking 대입으로 입력을 바꿔, DUT 가 같은 edge 에 샘플하는 것과 순서 경쟁이 생겼다.
  iverilog 와 Xcelium 의 `stat` 숫자가 12 cycle 달랐음 → 입력을 반대 edge (negedge) 에서 바꾸도록 수정 → 두 시뮬레이터 바이트 동일.
- **GLS FF 미실시** : min SDF 로 elaboration 하면 xmelab 이 `Building instance specific data structures` 단계에서 끝나지 않는다 (12 시간 이상).
  `-neg_tchk` 제거, `-notimingchecks` 모두 같음. 같은 fast 셀 모델로 SDF 없이 elaborate 하면 5 초. min SDF 는 max 와 구조 (CELL 69,142 · INTERCONNECT 110,278) 가 같고
  PATHPULSE · COND 없음, 음수 값 개수도 칩 v2 min SDF 와 비슷 → 원인 미확인, 툴 쪽 문제로 추정해 기록만 함.
  FF hold 는 P&R STA (FF view, +0.006 ns · 위반 0) 로 대신한다. SS/FF GLS 를 모두 통과한 대표 결과는 칩 v2.
