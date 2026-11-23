# ============================================================
# RV32I MCU (mcu_top) - core-level SDC, two asynchronous clocks (spec 11)
#
#   CLK_SYS  : core, bus, APB, GPIO, Timer, TEST, UART PCLK   100 MHz  port i_clkSys
#   CLK_UART : UART V4 baud / shifting side                    48 MHz  port i_clkUart
#
# CDC : the only crossings are inside uart_v4_apb. Same policy as UART V4
#   (no set_clock_groups -asynchronous : every crossing keeps a max delay of
#   the shorter period, which bounds Gray-pointer skew and the quasi-static
#   config bus ; hold across the clocks is false).
# I/O : GPIO in -> 2-FF synchronizer, UART rx -> synchronizer : asynchronous.
#       GPIO out / halt are CLK_SYS flops ; budget 40 % of the period.
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

# ---------------- CDC (inside the UART) ----------------
set_max_delay $CDC_MAX -from [get_clocks CLK_SYS]  -to [get_clocks CLK_UART]
set_max_delay $CDC_MAX -from [get_clocks CLK_UART] -to [get_clocks CLK_SYS]
set_false_path -hold   -from [get_clocks CLK_SYS]  -to [get_clocks CLK_UART]
set_false_path -hold   -from [get_clocks CLK_UART] -to [get_clocks CLK_SYS]

# ---------------- ports ----------------
set_false_path -from [get_ports i_rst_n]
set_false_path -from [get_ports i_uartRx]
set_false_path -to   [get_ports o_uartTx]
set_false_path -from [get_ports {i_gpioIn[*]}]

set_output_delay -max $OUT_DELAY -clock CLK_SYS [get_ports {o_gpioOut[*] o_halt}]
set_output_delay -min 0.0        -clock CLK_SYS [get_ports {o_gpioOut[*] o_halt}]

set_driving_cell -lib_cell BUFX2 -pin Y [remove_from_collection [all_inputs] [get_ports {i_clkSys i_clkUart}]]
set_load 0.01 [all_outputs]
