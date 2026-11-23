########################################
# EcoDrc : fix the remaining route DRC after ChipFinish, re-check, re-write outputs
#   from APR/work :  innovus -files ../scripts/6_EcoDrc.tcl -log ../log/eco_drc
#   (M4 first run : 1 Metal1 ParallelRunLength spacing inside u_rom)
########################################

restoreDesign ChipFinish.dat mcu_top

## ECO route : ecoRoute -fix_drc alone left the violation (1st try).
## Rip up only the two nets of the marker and route them again.
set ECO_NETS {u_rom/FE_OFN2998_n_1500 u_rom/n_958}
editDelete -net $ECO_NETS
ecoRoute
ecoRoute -fix_drc

## Verify
verify_drc -limit 1000 -report mcu_top.final_drc_eco.rpt
verifyConnectivity -type all -error 1000 -warning 50 -report mcu_top.final_conn_eco.rpt
timeDesign -postRoute       -outDir reports/eco -prefix eco
timeDesign -postRoute -hold -outDir reports/eco -prefix eco

## Outputs (overwrite the ChipFinish ones)
streamOut outputs/mcu_top.gds -libName DesignLib -units 2000 -mode ALL
saveNetlist -flat outputs/mcu_top_pnr.v
saveNetlist outputs/mcu_top_pnr_hier.v          ;# hierarchical : matches the SDF names (GLS)
write_sdf -view FUNC_SS_WORST -recrem split outputs/mcu_top_pnr_max.sdf
write_sdf -view FUNC_FF_BEST  -recrem split outputs/mcu_top_pnr_min.sdf
rcOut -spef outputs/mcu_top_worst.spef -rc_corner WORST
defOut -floorplan -netlist -routing outputs/mcu_top.def

summaryReport -noHtml -outfile reports/summary_eco.rpt
saveDesign ChipFinish_eco
exit
