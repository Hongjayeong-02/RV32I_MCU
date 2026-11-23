########################################
# InitDesign (Setup, Floorplan) : mcu_top (core-only, two clocks)
########################################
source ../scripts/apr_setup.tcl

set init_verilog   $NETLIST
set init_mmmc_file ../scripts/mcu_top.mmmc.view
set init_top_cell  $DESIGN
set init_pwr_net   VDD
set init_gnd_net   VSS
init_design

globalNetConnect VDD -type pgpin -pin VDD -inst * -override
globalNetConnect VSS -type pgpin -pin VSS -inst * -override

checkDesign -netlist -physicalLibrary -powerGround -timingLibrary -floorplan -outdir checkDesign

## Floorplan : square, UTIL (default 60 %), core-to-boundary MARGIN um (power ring)
floorPlan -site CoreSite -r 1.0 $UTIL $MARGIN $MARGIN $MARGIN $MARGIN

## Pins (14) : Left = clocks / reset, Right = GPIO, Top = UART / halt
set pins_left  [list i_clkSys i_clkUart i_rst_n]
set pins_right [concat [dbGet top.terms.name i_gpioIn*] [dbGet top.terms.name o_gpioOut*]]
set pins_top   [list i_uartRx o_uartTx o_halt]
editPin -side Left  -layer 3 -spreadType center -spacing 10.0 -unit MICRON -fixOverlap 1 -pin $pins_left
editPin -side Right -layer 3 -spreadType center -spacing 6.0  -unit MICRON -fixOverlap 1 -pin $pins_right
editPin -side Top   -layer 2 -spreadType center -spacing 10.0 -unit MICRON -fixOverlap 1 -pin $pins_top

report_analysis_views
timeDesign -prePlace -outDir reports/prePlace

saveDesign InitDesign
