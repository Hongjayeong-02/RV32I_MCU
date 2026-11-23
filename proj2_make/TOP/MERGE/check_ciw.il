; CIW checks after SEALRING / Move Origin / LOGO  (expected for DIE 1000 : chip 1020 x 1020)
cv = dbOpenCellViewByType("MCU_MERGE" "mcu_chip_final" "layout")
cv~>bBox                                                    ; ((0.0 0.0) (1020.0 1020.0)) top cell mcu_chip_final
setof(s cv~>shapes s~>layerName == "SEALRING")~>bBox        ; seal ring rectangle
setof(i cv~>instances i~>cellName == "MCU_LOGO")~>xy        ; logo instance origin
