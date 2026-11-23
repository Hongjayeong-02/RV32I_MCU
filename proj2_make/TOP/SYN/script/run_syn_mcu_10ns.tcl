# ============================================================
# RV32I MCU - Genus synthesis, core level (mcu_top), M4
#   CLK_SYS 100 MHz, CLK_UART 48 MHz (asynchronous), SS corner std cell lib
#
# Run from SYN/ :
#   genus -files script/run_syn_mcu_10ns.tcl -log log/syn_mcu_10ns
#   setenv MCU_PROG p03_uart   (optional) : which firmware fills the case ROM
#
# Library path: not written here (PDK paths stay off GitHub).
#   1. env MCU_STD_LIB, if set
#   2. else the LIB_PATH line of the UART V3 10 ns script in ~/PROJ1 (same as UART V4)
# ============================================================

# ------------------------------------------------------------
# 1. Directories
# ------------------------------------------------------------
set SCRIPT_DIR  [file dirname [file normalize [info script]]]
set SYN_DIR     [file normalize [file join $SCRIPT_DIR ..]]
set TOP_DIR     [file normalize [file join $SYN_DIR ..]]
set RTL_DIR     [file join $TOP_DIR RTL MCU_V1]
set PROG_NAME   [expr {[info exists env(MCU_PROG)] ? $env(MCU_PROG) : "p03_uart"}]
set ROM_FILE    [file join $TOP_DIR SIM PROG $PROG_NAME rv32_rom.v]

set REPORT_DIR  [file join $SYN_DIR report_mcu_10ns]
set NETLIST_DIR [file join $SYN_DIR netlist_mcu_10ns]
set FV_DIR      [file join $SYN_DIR fv]
file mkdir $REPORT_DIR $NETLIST_DIR $FV_DIR

# ------------------------------------------------------------
# 2. Library
# ------------------------------------------------------------
proc find_lib_path {} {
        global env
        if {[info exists env(MCU_STD_LIB)]} {
                return $env(MCU_STD_LIB)
        }
        set cands [glob -nocomplain \
                [file join $env(HOME) PROJ1 proj1_make TOP SYN script run_synthesis_10ns_rsync.tcl] \
                [file join $env(HOME) PROJ1 proj1_make TOP SYN run_synthesis_10ns_rsync.tcl] \
                [file join $env(HOME) PROJ1 proj1_make TOP SYN script run_synthesis_10ns.tcl] \
                [file join $env(HOME) PROJ1 proj1_make TOP SYN run_synthesis_10ns.tcl]]
        foreach f $cands {
                set fh [open $f r]
                set txt [read $fh]
                close $fh
                if {[regexp {set\s+LIB_PATH\s+"([^"]+)"} $txt -> p]} {
                        puts "INFO: LIB_PATH taken from $f"
                        return $p
                }
        }
        error "LIB_PATH not found: setenv MCU_STD_LIB <std cell .lib> and rerun"
}

set LIB_PATH [find_lib_path]
if {![file exists $LIB_PATH]} {
        error "LIB_PATH does not exist: $LIB_PATH"
}
set_db init_lib_search_path [file dirname $LIB_PATH]
set_db library $LIB_PATH

# ------------------------------------------------------------
# 3. RTL
# ------------------------------------------------------------
if {![file exists $ROM_FILE]} { error "ROM not found: $ROM_FILE" }
puts "INFO: ROM firmware = $PROG_NAME"

set RTL_FILES [concat \
        [list $ROM_FILE] \
        [glob [file join $RTL_DIR *.v]] \
        [glob [file join $RTL_DIR uart_v4 *.v]]]

set_db init_hdl_search_path [list $RTL_DIR]
set_db information_level 7
set_db hdl_track_filename_row_col true
set_db auto_ungroup none                ;# keep the hierarchy : per-block area / count

read_hdl $RTL_FILES
elaborate mcu_top
check_design -unresolved
check_design -all > [file join $REPORT_DIR check_design.rpt]

# ------------------------------------------------------------
# 4. Constraints
# ------------------------------------------------------------
read_sdc [file join $SYN_DIR cons mcu_top_10ns.sdc]
report_clocks > [file join $REPORT_DIR clocks.rpt]

# ------------------------------------------------------------
# 5. Synthesis
# ------------------------------------------------------------
syn_generic
syn_map
syn_opt

# ------------------------------------------------------------
# 6. Reports
# ------------------------------------------------------------
report_qor                                > [file join $REPORT_DIR qor.rpt]
report_area                               > [file join $REPORT_DIR area.rpt]
report_gates                              > [file join $REPORT_DIR gates.rpt]
report_timing -max_paths 20               > [file join $REPORT_DIR timing.rpt]
report_timing -group CLK_SYS  -max_paths 5 > [file join $REPORT_DIR timing_clk_sys.rpt]
report_timing -from [get_clocks CLK_SYS] -to [get_clocks CLK_UART] -max_paths 5 > [file join $REPORT_DIR timing_cdc_s2u.rpt]
report_timing -from [get_clocks CLK_UART] -to [get_clocks CLK_SYS] -max_paths 5 > [file join $REPORT_DIR timing_cdc_u2s.rpt]
report_power                              > [file join $REPORT_DIR power.rpt]

# one-line summary (per-block counts : area.rpt, hierarchical)
set fp [open [file join $REPORT_DIR summary.txt] w]
puts $fp [format "mcu_top inst=%d seq=%d area=%s rom=%s" \
        [llength [get_db insts]] [llength [get_db insts -if {.is_sequential}]] [get_db designs .area] $PROG_NAME]
close $fp

# ------------------------------------------------------------
# 7. Outputs (netlist, SDC, LEC do-file for Conformal on the LEC server)
# ------------------------------------------------------------
write_hdl > [file join $NETLIST_DIR mcu_top_10ns.v]
write_sdc > [file join $NETLIST_DIR mcu_top_10ns.sdc]
write_do_lec -revised_design [file join $NETLIST_DIR mcu_top_10ns.v] \
             -logfile [file join $FV_DIR lec_mcu_10ns.log] > [file join $FV_DIR rtl2gate_mcu_10ns.do]

puts "INFO: done. see [file join $REPORT_DIR summary.txt]"
exit
