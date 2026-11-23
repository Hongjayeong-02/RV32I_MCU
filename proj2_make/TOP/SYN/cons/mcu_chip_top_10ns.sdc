# ============================================================
# RV32I MCU chip level (mcu_chip_top, M5) - every port through an I/O PAD
#
#   Same clocks / CDC / I/O policy as the core-level SDC (mcu_top_10ns.sdc).
#   Clocks are defined on the chip ports : the input PAD (PADDI) delay is part
#   of the clock network (ideal in synthesis, propagated after CTS).
#   Differences from the core level :
#     - inputs are driven from off chip : set_input_transition (as UART V3 PADALL)
#       instead of a std-cell driving cell
#     - GPIO out / halt budget (40 % of CLK_SYS) now includes the output PAD
#
#   CLK_SYS  : core, bus, APB, GPIO, Timer, TEST, UART PCLK   100 MHz  port i_clkSys
#   CLK_UART : UART V4 baud / shifting side                    48 MHz  port i_clkUart
# ============================================================

set SYS_PERIOD   10.0
set UART_PERIOD  20.833
set CDC_MAX      [expr {($SYS_PERIOD < $UART_PERIOD) ? $SYS_PERIOD : $UART_PERIOD}]
set OUT_DELAY    [expr {$SYS_PERIOD * 0.4}]

create_clock -name CLK_SYS  -period $SYS_PERIOD  -waveform [list 0.0 [expr {$SYS_PERIOD / 2.0}]]  [get_ports i_clkSys]
create_clock -name CLK_UART -period $UART_PERIOD -waveform [list 0.0 [expr {$UART_PERIOD / 2.0}]] [get_ports i_clkUart]
set_clock_uncertainty -setup 0.10 [get_clocks {CLK_SYS CLK_UART}]
set_clock_uncertainty -hold  0.05 [get_clocks {CLK_SYS CLK_UART}]
set_clock_transition  0.05        [get_clocks {CLK_SYS CLK_UART}]

# CDC (inside uart_v4_apb) : max delay of the shorter period, no hold check across
set_max_delay $CDC_MAX -from [get_clocks CLK_SYS]  -to [get_clocks CLK_UART]
set_max_delay $CDC_MAX -from [get_clocks CLK_UART] -to [get_clocks CLK_SYS]
set_false_path -hold   -from [get_clocks CLK_SYS]  -to [get_clocks CLK_UART]
set_false_path -hold   -from [get_clocks CLK_UART] -to [get_clocks CLK_SYS]

# asynchronous inputs / output (each goes through a synchronizer or is sampled off chip asynchronously)
set_false_path -from [get_ports i_rst_n]
set_false_path -from [get_ports i_uartRx]
set_false_path -to   [get_ports o_uartTx]
set_false_path -from [get_ports {i_gpioIn[*]}]

# synchronous outputs : CLK_SYS flop -> PADDO -> pin within 60 % of the period
set_output_delay -max $OUT_DELAY -clock CLK_SYS [get_ports {o_gpioOut[*] o_halt}]
set_output_delay -min 0.0        -clock CLK_SYS [get_ports {o_gpioOut[*] o_halt}]

set_input_transition 0.5 [remove_from_collection [all_inputs] [get_ports {i_clkSys i_clkUart}]]
set_load 0.01 [all_outputs]

