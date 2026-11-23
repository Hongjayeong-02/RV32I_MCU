#!/bin/bash
# make_lec_pkg.sh : collect everything Conformal LEC needs into one folder (run on kopo-seongnam)
#   cd LEC ; bash make_lec_pkg.sh      -> ~/lec_mcu_pkg.tar.gz  (move to hitech001 through the PC)
#   LEC 1 : RTL            vs  synthesis netlist : Genus-written dofile (TOP/SYN/rtl2gate_pkg.do)
#           (rtl2syn.do = plain flat compare, kept for reference ; it reports
#            false non-equivalences on this design, use the Genus flow)
#   LEC 2 : synthesis      vs  P&R netlist       (APR/work/outputs/mcu_top_pnr.v)
#   The std-cell .lib is copied into the package (taken from the UART V3 10 ns
#   synthesis script, same as Genus) : the package is never committed.
cd "$(dirname "$0")" || exit 1
TOP=$(cd .. && pwd)
PROGNAME=${MCU_PROG:-p03_uart}
OUT=~/lec_mcu_pkg
rm -rf $OUT ; mkdir -p $OUT/rtl $OUT/netlist $OUT/lib

LIB=${MCU_STD_LIB:-$(grep -h 'set LIB_PATH "' ~/PROJ1/proj1_make/TOP/SYN/script/run_synthesis_10ns_rsync.tcl \
      ~/PROJ1/proj1_make/TOP/SYN/script/run_synthesis_10ns.tcl 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/')}
[ -f "$LIB" ] || { echo "ERROR: std cell lib not found (setenv MCU_STD_LIB ...)"; exit 1; }
cp "$LIB" $OUT/lib/std_ss.lib

cp $TOP/RTL/MCU_V1/*.v $TOP/RTL/MCU_V1/uart_v4/*.v $OUT/rtl/
cp $TOP/RTL/MCU_V1/rv32_defs.vh $OUT/rtl/ ; cp $TOP/RTL/MCU_V1/rv32_defs.vh $OUT/
cp $TOP/SIM/PROG/$PROGNAME/rv32_rom.v $OUT/rtl/
cp $TOP/SYN/netlist_mcu_10ns/mcu_top_10ns.v $OUT/netlist/ || exit 1
cp $TOP/APR/work/outputs/mcu_top_pnr.v      $OUT/netlist/ || exit 1

RTL_LIST=$(cd $OUT && ls rtl/*.v | tr '\n' ' ')

# flatten model : same as the dofile Genus writes (SYN/fv/rtl2gate_*.do).
#   -nodff_to_dlat_feedback is the key one : Genus builds hold-enable flops
#   as scan flops with D = Q and the new value on SI / SE ; LEC's default
#   would turn such a D=Q flop into a latch and lose the SE/SI path.
FLATTEN="set flatten model -seq_constant
set flatten model -seq_constant_x_to 0
set flatten model -nodff_to_dlat_zero
set flatten model -nodff_to_dlat_feedback
set flatten model -hier_seq_merge
set flatten model -balanced_modeling"

cat > $OUT/rtl2syn.do <<EOD
// LEC 1 : RTL (golden) vs Genus netlist (revised) -- mcu_top, ROM = $PROGNAME
set log file rtl2syn.log -replace
read library -liberty -both lib/std_ss.lib
set undriven signal 0 -golden
read design -define SYNTHESIS -verilog2k -golden -sensitive -root mcu_top $RTL_LIST
read design -verilog -revised -sensitive -root mcu_top netlist/mcu_top_10ns.v
set root module mcu_top -both
$FLATTEN
set system mode lec
analyze datapath -verbose
add compared points -all
compare
report verification
report compare data -class nonequivalent -class abort -class notcompared
usage
exit -force
EOD

cat > $OUT/syn2pnr.do <<EOD
// LEC 2 : Genus netlist (golden) vs Innovus netlist after ECO (revised)
set log file syn2pnr.log -replace
read library -liberty -both lib/std_ss.lib
read design -verilog -golden  -sensitive -root mcu_top netlist/mcu_top_10ns.v
read design -verilog -revised -sensitive -root mcu_top netlist/mcu_top_pnr.v
set root module mcu_top -both
$FLATTEN
set system mode lec
add compared points -all
compare
report verification
report compare data -class nonequivalent -class abort -class notcompared
usage
exit -force
EOD

# ---- LEC 1 (Genus flow) : the dofile Genus wrote (SYN/fv/rtl2gate_mcu_10ns.do)
#   RTL -> fv_map (hierarchical, datapath analysis) -> Genus netlist.
#   Copied with its fv/ data and the same relative layout, kopo absolute paths
#   rewritten to relative ones ; run it from lec_mcu_pkg/TOP/SYN.
G=$OUT/TOP
mkdir -p $G/RTL/MCU_V1/uart_v4 $G/SIM/PROG/$PROGNAME $G/SYN
cp $TOP/RTL/MCU_V1/*.v $TOP/RTL/MCU_V1/*.vh $G/RTL/MCU_V1/
cp $TOP/RTL/MCU_V1/uart_v4/*.v $G/RTL/MCU_V1/uart_v4/
cp $TOP/SIM/PROG/$PROGNAME/rv32_rom.v $G/SIM/PROG/$PROGNAME/
cp -r $TOP/SYN/fv $TOP/SYN/netlist_mcu_10ns $G/SYN/
sed -e "s|$TOP/|../|g" -e "s|$LIB|../../lib/std_ss.lib|g" \
    $TOP/SYN/fv/rtl2gate_mcu_10ns.do > $G/SYN/rtl2gate_pkg.do
echo 'exit' >> $G/SYN/rtl2gate_pkg.do
if grep -q "/home/" $G/SYN/rtl2gate_pkg.do; then
  echo "WARNING : absolute /home path left in rtl2gate_pkg.do :"; grep -n "/home/" $G/SYN/rtl2gate_pkg.do | head -5
fi

cd ~ && tar czf lec_mcu_pkg.tar.gz lec_mcu_pkg && ls -l ~/lec_mcu_pkg.tar.gz
echo "next : move ~/lec_mcu_pkg.tar.gz to hitech001 (MobaXterm), then"
echo "  tar xzf lec_mcu_pkg.tar.gz"
echo "  cd lec_mcu_pkg/TOP/SYN ; lec -xl -nogui -dofile rtl2gate_pkg.do   (LEC 1, Genus flow)"
echo "  cd ~/lec_mcu_pkg        ; lec -xl -nogui -dofile syn2pnr.do       (LEC 2)"
