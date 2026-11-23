# -----------------------------------------------------------------------------
# run_syn_ram_sweep.tcl : rv32_ram standalone synthesis, one size per run
#   cd SYN/script ; setenv RAM_AW 8 ; genus -files run_syn_ram_sweep.tcl -log ../log/ram_aw8
#   (run_ram_sweep.csh loops RAM_AW = 6 7 8 9 -> 256 B / 512 B / 1 KB / 2 KB)
#
# Library path: not written here (PDK paths stay off GitHub).
#   1. setenv MCU_STD_LIB <std cell slow .lib>   or
#   2. SYN/script/lib_setup.tcl (git-ignored) that sets LIB_PATH
# -----------------------------------------------------------------------------
set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set SYN_DIR     [file normalize [file join $SCRIPT_DIR ..]]
set RTL_DIR     [file normalize [file join $SYN_DIR .. RTL MCU_V1]]
set REPORT_DIR  [file join $SYN_DIR report_ram_sweep]
set NETLIST_DIR [file join $SYN_DIR netlist_ram_sweep]
file mkdir $REPORT_DIR $NETLIST_DIR

if {[info exists ::env(MCU_STD_LIB)]} {
        set LIB_PATH $::env(MCU_STD_LIB)
} elseif {[file exists [file join $SCRIPT_DIR lib_setup.tcl]]} {
        source [file join $SCRIPT_DIR lib_setup.tcl]
} else {
        error "LIB_PATH not found: setenv MCU_STD_LIB <std cell .lib> or create script/lib_setup.tcl"
}
if {![file exists $LIB_PATH]} { error "LIB_PATH does not exist: $LIB_PATH" }
set_db init_lib_search_path [file dirname $LIB_PATH]
set_db library $LIB_PATH

set AW    $::env(RAM_AW)
set BYTES [expr {(1 << $AW) * 4}]
set TAG   "ram_${BYTES}B"

set_db init_hdl_search_path $RTL_DIR
set_db information_level 7
read_hdl rv32_ram.v
elaborate rv32_ram -parameters [list [list ADDR_W $AW]]
set TOP [get_db designs]
check_design -unresolved

read_sdc [file join $SYN_DIR cons rv32_ram_10ns.sdc]

syn_generic
syn_map
syn_opt

report_qor                   > [file join $REPORT_DIR ${TAG}_qor.rpt]
report_area                  > [file join $REPORT_DIR ${TAG}_area.rpt]
report_gates                 > [file join $REPORT_DIR ${TAG}_gates.rpt]
report_timing -max_paths 5   > [file join $REPORT_DIR ${TAG}_timing.rpt]

set N_INST [llength [get_db insts]]
set N_SEQ  [llength [get_db insts -if {.is_sequential}]]
set fp [open [file join $REPORT_DIR summary.txt] a]
puts $fp [format "%-10s ADDR_W=%d  inst=%7d  seq=%6d  comb=%7d  area=%s" \
          $TAG $AW $N_INST $N_SEQ [expr {$N_INST - $N_SEQ}] [get_db $TOP .area]]
close $fp

write_hdl > [file join $NETLIST_DIR ${TAG}_netlist.v]
exit
