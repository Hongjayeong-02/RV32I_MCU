# sim_env.sh : common paths / file lists for the PROJ2 simulation scripts (bash)
#   sourced by SIM/FUNCTION/run_m1.sh, SIM/REGRESS/run_core.sh, SIM/REGRESS/run_mcu.sh
SIM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP_DIR=$(cd "$SIM_DIR/.." && pwd)
PROJ_DIR=$(cd "$TOP_DIR/../.." && pwd)
RTL=$TOP_DIR/RTL/MCU_V1
TB=$SIM_DIR/TESTBENCH
PROG=$SIM_DIR/PROG
TOOLS=$PROJ_DIR/TOOLS

CORE_RTL="$RTL/rv32_core.v $RTL/rv32_decoder.v $RTL/rv32_imm_gen.v $RTL/rv32_regfile.v \
$RTL/rv32_alu.v $RTL/rv32_branch.v $RTL/rv32_forward.v $RTL/rv32_hazard.v $RTL/rv32_lsu.v \
$RTL/rv32_ram.v $RTL/rv32_csr.v"
MCU_RTL="$RTL/mcu_top.v $RTL/mcu_dbus.v $RTL/mcu_apb_bridge.v $RTL/mcu_gpio.v $RTL/mcu_timer.v \
$RTL/mcu_test.v $CORE_RTL $RTL/uart_v4/*.v"

XRUN="xrun -64bit -clean -timescale 1ns/1ps -access +r -incdir $RTL -incdir $TB"
