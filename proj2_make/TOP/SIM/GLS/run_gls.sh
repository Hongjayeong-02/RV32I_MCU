#!/bin/bash
# post-route GLS : P&R netlist + SDF (APR/work/outputs), firmware = the ROM inside the netlist (p03_uart)
#   cd SIM/GLS ; bash run_gls.sh prep    files, std-cell Verilog models, pass-flop name, SDF cmd files
#                bash run_gls.sh run     SS (max SDF) and FF (min SDF) runs + summary -> gls_results.txt
#   chip level (M5, PADs) : add "chip" -> bash run_gls.sh prep chip / run chip / probe chip
#     netlist APR/work_chip/outputs, TB -define CHIP, PAD Verilog models, files in SIM/GLS/chip/
#   UART console demo : add "demo" (netlist synthesized with MCU_PROG=d01_demo)
#     -> bash run_gls.sh prep chip demo / run chip demo
#     TB tb_mcu_demo, console compared with PROG/d01_demo/console.golden (= RTL console)
#     files sdf_demo_*.cmd, gl_demo_*, gls_demo_results.txt (probe : tb_mcu only)
#     NOTE : with the demo chip netlist the min-SDF run never finishes elaboration
#     (xmelab stays in 'Building instance specific data structures', also without
#     -neg_tchk / with -notimingchecks ; fine without SDF). Stop it after the max run
#     (kill the xmelab) and use the P&R FF-view hold STA instead. See README.
# Same method as UART V4 (5_gls/glv4.sh) : -neg_tchk -nonotifier, timing violations reported
# and split into "synchronizer 1st stage" (expected with asynchronous inputs) and "other".
# Std-cell model directory : env MCU_STD_V, else the STD= line of the UART V4 glv4.sh on this server.
cd "$(dirname "$0")" || exit 1
source ../sim_env.sh
CHIP=0; DEMO=0
for a in "${@:2}"; do
  [ "$a" = chip ] && CHIP=1
  [ "$a" = demo ] && DEMO=1
done
if [ $CHIP = 1 ]; then
  OUTS=$TOP_DIR/APR/work_chip/outputs; BASE=mcu_chip_top; H=u_mcu.; DEFS="-define GLS -define CHIP"
  mkdir -p chip && cd chip || exit 1
else
  OUTS=$TOP_DIR/APR/work/outputs;      BASE=mcu_top;      H="";     DEFS="-define GLS"
fi
# hierarchical P&R netlist : write_sdf keeps the hierarchy (u_uart/g2717/Y), so a
# "saveNetlist -flat" netlist (\u_uart/g2717) leaves most SDF entries unannotated (SDFINF).
#   Innovus : restoreDesign ChipFinish_eco.dat mcu_top ; saveNetlist outputs/mcu_top_pnr_hier.v
NET=$OUTS/${BASE}_pnr_hier.v
TEST=p03_uart; TBN=tb_mcu; PFX=""; RTLLOG=mcu_p03_uart; EXTRA=""
if [ $DEMO = 1 ]; then
  TEST=d01_demo; TBN=tb_mcu_demo; PFX=demo_
  RTLLOG=$([ $CHIP = 1 ] && echo demo_chip || echo demo_mcu)
fi
SYNC_RE="r_sync1|Sync1|rxMeta|rstSync|r_meta|u_rst_sys|u_prst|u_urst|sync_reg\[0\]"

find_std() {
  if [ -n "$MCU_STD_V" ]; then echo "$MCU_STD_V"; return; fi
  for f in $(find ~ -maxdepth 4 -name glv4.sh 2>/dev/null); do
    grep -q '<PDK>' "$f" && continue
    l=$(grep -m1 '^STD=' "$f") || continue
    eval "$l"; echo "$STD"; return
  done
}
STD=$(find_std)
[ -d "$STD" ] || { echo "ERROR: std-cell Verilog model dir not found (setenv MCU_STD_V <dir>)"; exit 1; }
CELL_MAX=$(ls $STD/*.v | grep -iE 'slow|_ss' | head -1)
CELL_MIN=$(ls $STD/*.v | grep -iE 'fast|_ff' | head -1); [ -f "$CELL_MIN" ] || CELL_MIN=$CELL_MAX

# PAD Verilog models (chip only) : env MCU_PAD_V, else the PAD= line of the UART V3 PADALL glro.sh
find_pad() {
  if [ -n "$MCU_PAD_V" ]; then echo "$MCU_PAD_V"; return; fi
  for f in $(find ~ -maxdepth 4 -name glro.sh 2>/dev/null); do
    grep -q '<PDK>' "$f" && continue
    eval "$(grep -E '^(G?PDK|GIO)[A-Za-z_0-9]*=' "$f")"
    l=$(grep -m1 '^PAD=' "$f") || continue
    eval "$l"; echo "$PAD"; return
  done
}
PAD_MAX=""; PAD_MIN=""
if [ $CHIP = 1 ]; then
  PADD=$(find_pad)
  [ -d "$PADD" ] || { echo "ERROR: PAD Verilog model dir not found (setenv MCU_PAD_V <dir>)"; exit 1; }
  PAD_MAX=$(ls $PADD/*.v | grep -iE 'slow|_ss' | head -1)
  PAD_MIN=$(ls $PADD/*.v | grep -iE 'fast|_ff' | head -1); [ -f "$PAD_MIN" ] || PAD_MIN=$PAD_MAX
fi

if [ "$1" = prep ]; then
  for f in $NET $OUTS/${BASE}_pnr_max.sdf $OUTS/${BASE}_pnr_min.sdf $CELL_MAX $TB/$TBN.v $PAD_MAX; do
    [ -f $f ] && echo "ok   $(basename $f)" || { echo "MISSING $f"; exit 1; }
  done
  echo "cell model : max $(basename $CELL_MAX) / min $(basename $CELL_MIN)"
  [ $CHIP = 1 ] && echo "PAD model  : max $(basename $PAD_MAX) / min $(basename $PAD_MIN)"
  # pass flop of the TEST device in the flat netlist (name kept by synthesis / P&R)
  grep -q ' o_pass_reg ' $NET && P=${H}u_test.o_pass_reg
  [ -n "$P" ] || { echo "ERROR: TEST pass flop not found in the netlist (grep o_pass_reg $NET)"; exit 1; }
  printf '`define GLS_PASS dut.%s .Q\n' "$P" > gls_pass.vh
  echo "pass flop  : $(cat gls_pass.vh)"
  for m in max min; do
    M=$([ $m = max ] && echo MAXIMUM || echo MINIMUM)
    printf 'SDF_FILE = "%s/%s_pnr_%s.sdf",\nSCOPE = %s.dut,\nLOG_FILE = "sdf_%s%s.log",\nMTM_CONTROL = "%s",\nSCALE_TYPE = "FROM_%s";\n' \
      $OUTS $BASE $m $TBN $PFX $m $M $M > sdf_$PFX$m.cmd
  done
  echo "netlist    : $(grep -c '^module' $NET) module(s), $(grep -cE '^ *[A-Z][A-Z0-9]+X[0-9L]* ' $NET) cell lines, PAD $(grep -cE '^ *PADD[IO] ' $NET)"
  ls sdf_$PFX*.cmd
  exit 0
fi

if [ "$1" = probe ]; then
  # debug : print reset / halt / PC flops every 10 cycles for the first 3 us
  #   zero-delay run (no SDF) and max-SDF run -> tells a functional/X problem from a timing problem
  SIG=""; FMT=""
  for b in 13 12 11 10 9 8 7 6 5 4 3 2; do
    grep -q "\\\\r_pc_reg\[$b\] " $NET && { SIG="$SIG, tb_mcu.dut.${H}u_core.\\r_pc_reg[$b] .Q"; FMT="$FMT%b"; }
  done
  R="r_sync_reg[0] r_sync_reg[1]"
  RS=""; RF=""
  for r in $R; do RS="$RS, tb_mcu.dut.${H}u_rst_sys.\\$r .Q"; RF="$RF%b"; done
  echo "pc bits    : $(echo "$FMT" | tr -cd 'b' | wc -c) found, reset-sync flops : $R"
  {
    echo 'module gls_probe;'
    echo 'integer i;'
    echo 'initial begin'
    echo '  for (i = 0; i < 300; i = i + 1) begin'
    echo "    \$display(\"PROBE t=%0t rst_n=%b rsync=$RF halt=%b pass=%b clk=%b pc[13:2]=$FMT\", \$time, tb_mcu.r_rst_n$RS, tb_mcu.w_halt, tb_mcu.w_pass, tb_mcu.r_clkSys$SIG);"
    echo '    #10;'
    echo '  end'
    echo '  $finish;'
    echo 'end'
    echo 'endmodule'
  } > gls_probe.v
  for m in nosdf max; do
    SDFOPT=""; [ $m = max ] && SDFOPT="-sdf_cmd_file sdf_max.cmd"
    xrun -64bit -clean -access +r -neg_tchk -nonotifier -timescale 1ns/1ps $DEFS -incdir . $SDFOPT \
         $CELL_MAX $PAD_MAX $NET $TB/tb_mcu.v gls_probe.v -top tb_mcu -top gls_probe +TEST=$TEST -l probe_$m.log > /dev/null 2>&1
    echo "== probe_$m : *E $(grep -c '\*E,' probe_$m.log), SDFINF $(grep -c SDFINF probe_$m.log)"
    grep '\*E,' probe_$m.log | head -3
    grep 'PROBE' probe_$m.log | awk 'NR<=6 || NR%30==0'
  done
  exit 0
fi

[ "$1" = run ] || { echo "usage: bash run_gls.sh prep|run|probe [chip] [demo]"; exit 1; }
[ $DEMO = 1 ] && [ ! -f sdf_demo_max.cmd ] && { echo "run prep ... demo first"; exit 1; }
[ -f gls_pass.vh ] || { echo "run prep first"; exit 1; }
RTL_HALT=$(grep -o 'halt@[0-9]*' $SIM_DIR/REGRESS/log/$RTLLOG.log 2>/dev/null | head -1 | cut -d@ -f2)
RES=gls_${PFX}results.txt
{
echo "# post-route GLS (Xcelium) : $BASE P&R netlist + SDF, firmware $TEST (ROM in the netlist)"
echo "# RTL halt cycle : ${RTL_HALT:-unknown (run SIM/REGRESS/run_mcu.sh / run_demo.sh first)}"
echo
} > $RES
for m in max min; do
  CELL=$([ $m = max ] && echo $CELL_MAX || echo $CELL_MIN)
  PADV=$([ $m = max ] && echo $PAD_MAX || echo $PAD_MIN)
  L=gl_$PFX$m
  [ $DEMO = 1 ] && EXTRA="+CONSOLE=${L}_console.txt +GOLD=$PROG/$TEST/console.golden"
  echo "== RUN $L"
  xrun -64bit -clean -access +r -neg_tchk -nonotifier -sdf_verbose -timescale 1ns/1ps $DEFS \
       -incdir . -sdf_cmd_file sdf_$PFX$m.cmd $CELL $PADV $NET $TB/$TBN.v -top $TBN +TEST=$TEST $EXTRA -l $L.log > /dev/null 2>&1
  p=$(grep -c '^PASS' $L.log); f=$(grep -c '^FAIL' $L.log)
  h=$(grep -o 'halt@[0-9]*' $L.log | tail -1 | cut -d@ -f2)
  grep -A4 "Timing violation" $L.log | grep -o "Scope: [^ ;]*" | sed 's/Scope: //' > ${L}_viol_scope.txt
  t=$(wc -l < ${L}_viol_scope.txt); s=$(grep -cE "$SYNC_RE" ${L}_viol_scope.txt)
  {
    echo "$L : PASS $p / FAIL $f | $(grep 'ALL PASS\|FAIL ' $L.log | tail -1)"
    [ $DEMO = 1 ] && echo "    $(grep 'D4' $L.log | tail -1)"
    echo "    halt cycle $h (RTL ${RTL_HALT:-?}) $([ -n "$h" ] && [ "$h" = "$RTL_HALT" ] && echo '-> same' || echo '-> differs')"
    echo "    $(grep 'Annotation completed' $L.log | head -1 | sed 's/^ *//') | *E, $(grep -c '\*E,' $L.log) | SDFINF $(grep -c SDFINF $L.log) (must be 0)"
    echo "    timing violations $t (synchronizer 1st stage $s, other $((t - s)))"
    [ $((t - s)) -gt 0 ] && grep -vE "$SYNC_RE" ${L}_viol_scope.txt | sort | uniq -c | sort -rn | head -5 | sed 's/^/      /'
  } >> $RES
done
echo; cat $RES
