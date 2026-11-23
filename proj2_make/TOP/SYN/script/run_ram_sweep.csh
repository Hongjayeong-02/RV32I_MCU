#!/bin/tcsh -f
# rv32_ram sweep : 256 B / 512 B / 1 KB / 2 KB
#   cd SYN/script ; ./run_ram_sweep.csh
#   result : SYN/report_ram_sweep/summary.txt
mkdir -p ../log
rm -f ../report_ram_sweep/summary.txt
foreach aw ( 6 7 8 9 )
        echo "==== RAM_AW = $aw ===="
        setenv RAM_AW $aw
        genus -files run_syn_ram_sweep.tcl -log ../log/ram_aw$aw
end
echo ""
cat ../report_ram_sweep/summary.txt
