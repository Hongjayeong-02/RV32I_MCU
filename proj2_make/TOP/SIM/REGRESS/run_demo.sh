#!/bin/bash
# UART console demo (Xcelium) : tb_mcu_demo + firmware PROG/d01_demo
#   cd SIM/REGRESS ; bash run_demo.sh          DUT = mcu_top
#                    bash run_demo.sh chip     DUT = mcu_chip_top, PADs bypassed
#   the console is printed and saved to log/demo_<dut>_console.txt, and compared
#   byte by byte with PROG/d01_demo/console.golden (D4)
#   gate level : SIM/GLS/run_gls.sh run chip demo
cd "$(dirname "$0")" || exit 1
source ../sim_env.sh
mkdir -p log
T=d01_demo
DUT=mcu; CHIPOPT=""
if [ "$1" = chip ]; then DUT=chip; CHIPOPT="-define CHIP -define NO_PAD $RTL/mcu_chip_top.v"; fi
n=demo_$DUT

$XRUN $CHIPOPT $TB/tb_mcu_demo.v $PROG/$T/rv32_rom.v $MCU_RTL -top tb_mcu_demo \
   +CONSOLE=log/${n}_console.txt +GOLD=$PROG/$T/console.golden -l log/$n.log > /dev/null 2>&1

echo "== console (log/${n}_console.txt)"
cat log/${n}_console.txt
echo
echo "== checks (log/$n.log)"
grep "^PASS:\|^FAIL\|DEMO \|\*E," log/$n.log
