########################################
# MCU chip-level P&R (M5), all steps   (from APR/work_chip)
#   cd APR/scripts_chip ; bash make_pdk_setup_chip.sh      (once)
#   mkdir -p ../work_chip ; cd ../work_chip
#   innovus -files ../scripts_chip/run_all_chip.tcl -log ../log/apr_chip
#   other die size :  innovus -execute "set DIE 1100" -files ../scripts_chip/run_all_chip.tcl ...
########################################
file mkdir reports
source ../scripts_chip/0_InitDesign.tcl
source ../scripts_chip/1_PowerPlan.tcl
source ../scripts_chip/2_PlaceOpt.tcl
source ../scripts_chip/3_PostCTSopt.tcl
source ../scripts_chip/4_RouteDesign_PowerAnalysis.tcl
source ../scripts_chip/5_ChipFinish.tcl
exit
