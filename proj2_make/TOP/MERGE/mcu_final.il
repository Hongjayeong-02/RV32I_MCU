; mcu_final.il : CIW  load "<path to PROJ2>/proj2_make/TOP/MERGE/mcu_final.il"
;   1) shows which library got the Stream In cells (mcu_chip_top, PAD, std cells)
;   2) if mcu_chip_top is in MCU_MERGE : builds mcu_chip_final
;      (chip at (10,10), MCU_LOGO at (290,295), SEALRING (0,0)~(DIE+20,DIE+20))
let((top logo cv bb w h ichip)
  ; every library in cds.lib that holds one of the streamed-in cells
  ; (design / PAD / std cell) : no library names written here
  foreach(l ddGetLibList()
    when(ddGetObj(l~>name "mcu_chip_top") || ddGetObj(l~>name "padIORINGCORNER") || ddGetObj(l~>name "INVX1")
      printf("%-11s mcu_chip_top:%-3s padIORINGCORNER:%-3s INVX1:%-3s cells:%d\n" l~>name
        if(ddGetObj(l~>name "mcu_chip_top") "yes" "no")
        if(ddGetObj(l~>name "padIORINGCORNER") "yes" "no")
        if(ddGetObj(l~>name "INVX1") "yes" "no")
        length(l~>cells))))
  top  = dbOpenCellViewByType("MCU_MERGE" "mcu_chip_top" "layout")
  logo = dbOpenCellViewByType("MCU_MERGE" "MCU_LOGO" "layout")
  if(top && logo then
    ; mcu_chip_top~>bBox covers only its own shapes (80..920 : no PAD / std-cell
    ; content, the DIEAREA layer is not streamed) -> size the seal ring from the
    ; placed instance, whose bBox includes the PAD ring (die 0..DIE)
    cv = dbOpenCellViewByType("MCU_MERGE" "mcu_chip_final" "layout" "maskLayout" "w")
    ichip = dbCreateInst(cv top  "I_CHIP" list(10.0 10.0)   "R0")
    dbCreateInst(cv logo "I_LOGO" list(290.0 295.0) "R0")
    bb = ichip~>bBox
    w = caadr(bb) + 10.0
    h = cadadr(bb) + 10.0
    dbCreateRect(cv list("SEALRING" "drawing") list(list(0.0 0.0) list(w h)))
    dbSave(cv)
    printf("FINAL mcu_chip_final bBox = %L  (chip instance %L)\n" cv~>bBox bb)
  else
    printf("NOT BUILT : mcu_chip_top %s / MCU_LOGO %s in MCU_MERGE\n"
           if(top "ok" "missing") if(logo "ok" "missing"))
  )
)
