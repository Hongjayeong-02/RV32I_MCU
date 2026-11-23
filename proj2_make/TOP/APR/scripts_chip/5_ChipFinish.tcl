########################################
# ChipFinish : mcu_chip_top
########################################

# restoreDesign RouteDesign.dat mcu_chip_top

file mkdir outputs

## Core Filler
addFiller -cell {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -prefix FILLER

## Verify
checkPlace mcu_chip_top.checkPlace_final.rpt
verify_drc -limit 1000 -report mcu_chip_top.final_drc.rpt
verifyConnectivity -type all -error 1000 -warning 50 -report mcu_chip_top.final_conn.rpt
timeDesign -postRoute       -outDir reports/final -prefix final
timeDesign -postRoute -hold -outDir reports/final -prefix final
report_area > reports/final_area.rpt

## CDC paths (set_max_delay 10 ns, D23) after route
report_timing -clock_from CLK_SYS -clock_to CLK_UART -max_paths 50 > reports/final_cdc_s2u.rpt
report_timing -clock_from CLK_UART -clock_to CLK_SYS  -max_paths 50 > reports/final_cdc_u2s.rpt

## I/O paths through the PADs (synchronous outputs o_gpioOut / o_halt)
report_timing -to [all_outputs] -max_paths 10 > reports/final_r2o.rpt

## Output
streamOut outputs/mcu_chip_top.gds -libName DesignLib -units 2000 -mode ALL
saveNetlist -flat outputs/mcu_chip_top_pnr.v
saveNetlist outputs/mcu_chip_top_pnr_hier.v          ;# hierarchical : matches the SDF names (GLS)
write_sdf -view FUNC_SS_WORST -recrem split outputs/mcu_chip_top_pnr_max.sdf
write_sdf -view FUNC_FF_BEST  -recrem split outputs/mcu_chip_top_pnr_min.sdf
rcOut -spef outputs/mcu_chip_top_worst.spef -rc_corner WORST
defOut -floorplan -netlist -routing outputs/mcu_chip_top.def

## Save Design
summaryReport -noHtml -outfile reports/summary.rpt
saveDesign ChipFinish
