########################################
# MCU core-only P&R, all steps   (from APR/work)
#   innovus -files ../scripts/run_all.tcl -log ../log/apr_u60
#   other utilization :  innovus -execute "set UTIL 0.70" -files ../scripts/run_all.tcl ...
########################################
file mkdir reports
source ../scripts/0_InitDesign.tcl
source ../scripts/1_PowerPlan.tcl
source ../scripts/2_PlaceOpt.tcl
source ../scripts/3_PostCTSopt.tcl
source ../scripts/4_RouteDesign_PowerAnalysis.tcl
source ../scripts/5_ChipFinish.tcl
exit
