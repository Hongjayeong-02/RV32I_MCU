`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_regfile
//   31 x 32-bit registers, 2 read (ID, combinational) / 1 write (WB, posedge).
//   - x0 has no storage and always reads 0.
//   - write-first bypass: a WB write and an ID read of the same register in
//     the same cycle -> ID sees the NEW value (no extra forwarding needed for
//     the WB -> ID distance).
//   - registers reset to 0 (only the RAM data array is reset-free, spec 1).
// -----------------------------------------------------------------------------
module rv32_regfile (
        input   wire            i_clk,
        input   wire            i_rst_n,

        input   wire            i_we,
        input   wire    [4:0]   i_rd,
        input   wire    [31:0]  i_wdata,

        input   wire    [4:0]   i_rs1,
        input   wire    [4:0]   i_rs2,
        output  wire    [31:0]  o_rs1Val,
        output  wire    [31:0]  o_rs2Val
);

reg     [31:0]  r_x [1:31];
integer         k;

wire            w_wr = i_we & (i_rd != 5'd0);

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                for (k = 1; k < 32; k = k + 1) r_x[k] <= 32'd0;
        end else if (w_wr) begin
                r_x[i_rd] <= i_wdata;
        end
end

assign o_rs1Val = (i_rs1 == 5'd0)           ? 32'd0   :
                  (w_wr && (i_rd == i_rs1)) ? i_wdata :
                                              r_x[i_rs1];

assign o_rs2Val = (i_rs2 == 5'd0)           ? 32'd0   :
                  (w_wr && (i_rd == i_rs2)) ? i_wdata :
                                              r_x[i_rs2];

endmodule
