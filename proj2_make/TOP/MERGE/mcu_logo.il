; mcu_logo.il : LOGO layer "RV32" pixel letters -> cell MCU_MERGE/MCU_LOGO/layout
;   (UART V3 7_merge/uart_logo.il, other text)
; CIW:  load "mcu_logo.il"
; pixel 4 um, letter 5x7 pixels (20 x 28 um), gap 1 pixel  -> 116 x 28 um
let((cv px x0 font rows line y)
  px = 4.0
  font = list(
    list("11110" "10001" "10001" "11110" "10100" "10010" "10001")   ; R
    list("10001" "10001" "10001" "10001" "10001" "01010" "00100")   ; V
    list("11110" "00001" "00001" "01110" "00001" "00001" "11110")   ; 3
    list("01110" "10001" "00001" "00010" "00100" "01000" "11111")   ; 2
  )
  cv = dbOpenCellViewByType("MCU_MERGE" "MCU_LOGO" "layout" "maskLayout" "w")
  x0 = 0.0
  foreach(rows font
    for(r 0 6
      line = nth(r rows)
      for(c 0 4
        when(equal(substring(line c+1 1) "1")
          y = (6 - r) * px
          dbCreateRect(cv list("LOGO" "drawing")
                       list(list(x0 + c*px y) list(x0 + (c+1)*px y + px)))
        )
      )
    )
    x0 = x0 + 6*px
  )
  dbSave(cv)
  printf("MCU_LOGO bBox = %L\n" cv~>bBox)
  dbClose(cv)
)
