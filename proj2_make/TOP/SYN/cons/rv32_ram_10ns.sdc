# rv32_ram standalone synthesis (M0 RAM sweep), 10 ns baseline
#   i/o delay 3 ns = placeholder for the surrounding MEM-stage logic
create_clock -name clk_sys -period 10.0 [get_ports i_clk]
set_clock_uncertainty 0.2 [get_clocks clk_sys]
set_input_delay  3.0 -clock clk_sys [remove_from_collection [all_inputs] [get_ports i_clk]]
set_output_delay 3.0 -clock clk_sys [all_outputs]
