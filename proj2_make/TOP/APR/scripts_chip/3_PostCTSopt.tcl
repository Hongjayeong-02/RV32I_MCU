########################################
# CTS + postCTS Opt : mcu_chip_top (CLK_SYS 100 MHz, CLK_UART 48 MHz ; clock sources = input PAD Y)
########################################

# restoreDesign PlaceOpt.dat mcu_chip_top

## Analysis Mode : OCV + CPPR
setAnalysisMode -analysisType onChipVariation -cppr both

## CTS
set_ccopt_property buffer_cells   [dbGet head.libCells.name CLKBUF* -u]
set_ccopt_property inverter_cells [dbGet head.libCells.name CLKINV* -u]
create_ccopt_clock_tree_spec -file mcu_chip_top.ccopt.spec
ccopt_design

## postCTS Opt : setup -> hold
optDesign -postCTS       -outDir reports/postCTS_opt
setOptMode -holdTargetSlack 0.005
optDesign -postCTS -hold -outDir reports/postCTS_hold_opt

## Verify
checkPlace mcu_chip_top.checkPlace_postCTS.rpt
report_ccopt_clock_trees -file reports/postCTS_clock_trees.rpt
report_ccopt_skew_groups -file reports/postCTS_skew_groups.rpt
timeDesign -postCTS       -outDir reports/postCTS -prefix postCTS
timeDesign -postCTS -hold -outDir reports/postCTS -prefix postCTS

## Save Design
saveDesign PostCTSopt
