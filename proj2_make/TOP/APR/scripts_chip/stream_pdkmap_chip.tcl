########################################
# M5-5 : design-only GDS with the PDK's Innovus stream map (for the Virtuoso merge)
#   from APR/work_chip :  innovus  ->  source ../scripts_chip/stream_pdkmap_chip.tcl
#   no -merge : std-cell and IO GDS are merged in Virtuoso (same as UART V3 7_merge)
#   Without -mapFile Innovus numbers the layers itself and Metal lands on Via
#   layers of the PDK layermap (UART V3 : 182,058 shapes dropped, DRC 21,648).
########################################
# a STREAM_MAP set by hand in the Innovus session wins over pdk_lef_chip.tcl
if {[info exists STREAM_MAP]} { set _map $STREAM_MAP }
source ../scripts_chip/pdk_lef_chip.tcl
if {[info exists _map]} { set STREAM_MAP $_map }
if {![info exists STREAM_MAP] || ![file exists $STREAM_MAP]} {
  error "STREAM_MAP not set : setenv MCU_STREAM_MAP <streamOut.map> ; bash make_pdk_setup_chip.sh"
}
restoreDesign ChipFinish.dat mcu_chip_top
streamOut outputs/mcu_chip_top_pdkmap.gds -mapFile $STREAM_MAP \
          -libName DesignLib -units 2000 -mode ALL
puts "STREAM DONE : outputs/mcu_chip_top_pdkmap.gds"
