(globals
    version = 3
    io_order = default
)
# MCU chip PAD ring (M5) : 14 signal PADs + 8 power PADs + 4 corners
#   left   : clocks / reset / UART rx, core power
#   top    : GPIO in, IO-ring power
#   right  : GPIO out, core power
#   bottom : UART tx / halt, IO-ring power
#   positions are spread evenly by respace_chip.tcl (integer gaps for the IO fillers)
(iopad
    (topleft
        (inst name="CORNER_TL" cell="padIORINGCORNER")
    )
    (top
        (inst name="g_pad_gpioIn[0].u_pad")
        (inst name="g_pad_gpioIn[1].u_pad")
        (inst name="PVDDIOR_T" cell="PADVDDIOR")
        (inst name="PVSSIOR_T" cell="PADVSSIOR")
        (inst name="g_pad_gpioIn[2].u_pad")
        (inst name="g_pad_gpioIn[3].u_pad")
    )
    (topright
        (inst name="CORNER_TR" cell="padIORINGCORNER")
    )
    (left
        (inst name="u_pad_uartRx")
        (inst name="u_pad_rst_n")
        (inst name="PVDD_L" cell="PADVDD")
        (inst name="PVSS_L" cell="PADVSS")
        (inst name="u_pad_clkUart")
        (inst name="u_pad_clkSys")
    )
    (right
        (inst name="g_pad_gpioOut[3].u_pad")
        (inst name="g_pad_gpioOut[2].u_pad")
        (inst name="PVDD_R" cell="PADVDD")
        (inst name="PVSS_R" cell="PADVSS")
        (inst name="g_pad_gpioOut[1].u_pad")
        (inst name="g_pad_gpioOut[0].u_pad")
    )
    (bottomleft
        (inst name="CORNER_BL" cell="padIORINGCORNER")
    )
    (bottom
        (inst name="u_pad_uartTx")
        (inst name="PVDDIOR_B" cell="PADVDDIOR")
        (inst name="PVSSIOR_B" cell="PADVSSIOR")
        (inst name="u_pad_halt")
    )
    (bottomright
        (inst name="CORNER_BR" cell="padIORINGCORNER")
    )
)
