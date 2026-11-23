# M5-5 : Merge / Stream Out (Virtuoso) / PVS DRC - mcu_chip_top

Same flow as UART V3 `7_merge` (textbook vol.2 ch.13), applied to the MCU chip.

1. design-only GDS with the PDK Innovus stream map (Innovus, `APR/work_chip`)
   `source ../scripts_chip/stream_pdkmap_chip.tcl` -> `outputs/mcu_chip_top_pdkmap.gds`
2. Virtuoso : new library `MCU_MERGE` (attach the PDK tech library), Stream In with the PDK
   Virtuoso layermap, same cell names overwritten, in this order :
   design GDS -> std-cell GDS -> IO GDS
3. SEALRING (66:0) rectangle (-10,-10) ~ (DIE+10, DIE+10), Move Origin (-10,-10) -> (0,0),
   LOGO : `load "mcu_logo.il"` then place `MCU_LOGO` in an empty corner area ;
   check with `load "check_ciw.il"`
4. Stream Out `mcu_chip_final.gds`
5. PVS DRC with the same rule deck / options as UART V3 (`pvs -drc -dp 4`)

Results : see the M5 section of the top README.
Used in M5-5 : mcu_logo.il, mcu_final.il (GUI Stream In x3, then CIW load of mcu_final.il).
