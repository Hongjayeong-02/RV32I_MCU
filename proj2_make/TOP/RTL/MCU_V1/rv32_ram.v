`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_ram
//   FF-array data RAM : 2**ADDR_W words x 32-bit (ADDR_W=8 -> 1 KB, spec 7).
//   - synchronous write, 4 byte enables
//   - asynchronous (combinational) read -> load data in the same MEM cycle
//   - data array has NO reset on purpose (8,192 resettable FFs avoided);
//     crt0 initializes .data / .bss. Exception to the reset rule (spec 1).
//   M0 sweep (10 ns, slow corner): 1 KB = 15,226 inst, slack +2.458 ns.
// -----------------------------------------------------------------------------
module rv32_ram #(
        parameter ADDR_W = 8
)(
        input   wire                    i_clk,
        input   wire    [3:0]           i_be,
        input   wire    [ADDR_W-1:0]    i_addr,
        input   wire    [31:0]          i_wdata,

        output  wire    [31:0]          o_rdata
);

localparam DEPTH = (1 << ADDR_W);

reg     [31:0]  r_mem [0:DEPTH-1];

always @(posedge i_clk) begin
        if (i_be[0]) r_mem[i_addr][ 7: 0] <= i_wdata[ 7: 0];
        if (i_be[1]) r_mem[i_addr][15: 8] <= i_wdata[15: 8];
        if (i_be[2]) r_mem[i_addr][23:16] <= i_wdata[23:16];
        if (i_be[3]) r_mem[i_addr][31:24] <= i_wdata[31:24];
end

assign o_rdata = r_mem[i_addr];

endmodule
