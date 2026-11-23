########################################
# InitDesign (Setup, Floorplan, PAD ring) : mcu_chip_top (M5)
#   same as UART V3 PADALL : loadIoFile -> respace (integer gaps) -> IO filler
########################################
source ../scripts_chip/apr_setup_chip.tcl

set init_verilog   $NETLIST
set init_mmmc_file ../scripts_chip/mcu_chip_top.mmmc.view
set init_top_cell  $DESIGN
set init_pwr_net   {VDD VDDIOR}
set init_gnd_net   {VSS VSSIOR}
init_design

checkDesign -io -netlist -physicalLibrary -powerGround -timingLibrary -floorplan -outdir checkDesign

## Floorplan : die DIE x DIE, core 30 um inside the PAD ring (core power ring channel)
floorPlan -site CoreSite -d $DIE $DIE 30 30 30 30

## Signal routing up to Metal5 only (M5-5 DRC fix, v2)
#   The PVS deck rule VIAk.X.3/X.4 forbids single-cut vias stacked through 6 layers
#   (Metal1..6 ... Metal4..9). It is not in the LEF, so NanoRoute did not know it :
#   v1 had 122 such stacks, all in the core. Metal6..9 carry only the power grid.
setDesignMode -topRoutingLayer Metal5

## PAD ring
loadIoFile ../scripts_chip/mcu_chip.io

globalNetConnect VDD    -type pgpin -pin VDD    -inst * -override
globalNetConnect VSS    -type pgpin -pin VSS    -inst * -override
globalNetConnect VDDIOR -type pgpin -pin VDDIOR -inst * -override
globalNetConnect VSSIOR -type pgpin -pin VSSIOR -inst * -override

source ../scripts_chip/respace_chip.tcl
addIoFiller -cell {padIORINGFEED60 padIORINGFEED10 padIORINGFEED5 padIORINGFEED3 padIORINGFEED1} -prefix IOFILL

## Checks
checkFPlan -outFile reports/checkFPlan.rpt
report_analysis_views
timeDesign -prePlace -outDir reports/prePlace

saveDesign InitDesign
