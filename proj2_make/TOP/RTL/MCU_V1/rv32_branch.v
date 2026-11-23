`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_branch  (EX stage, combinational)
//   Conditional branch compare. Operands are the FORWARDED rs1 / rs2 values.
//   o_taken is meaningful only when the EX instruction is a branch.
//   funct3 010 / 011 are illegal (flagged by rv32_decoder) -> not taken.
// -----------------------------------------------------------------------------
module rv32_branch (
        input   wire    [2:0]   i_funct3,
        input   wire    [31:0]  i_rs1Val,
        input   wire    [31:0]  i_rs2Val,

        output  reg             o_taken
);

wire            w_eq  = (i_rs1Val == i_rs2Val);
wire            w_lt  = ($signed(i_rs1Val) < $signed(i_rs2Val));
wire            w_ltu = (i_rs1Val < i_rs2Val);

always @(*) begin
        case (i_funct3)
                3'b000  : o_taken =  w_eq;      // BEQ
                3'b001  : o_taken = ~w_eq;      // BNE
                3'b100  : o_taken =  w_lt;      // BLT
                3'b101  : o_taken = ~w_lt;      // BGE
                3'b110  : o_taken =  w_ltu;     // BLTU
                3'b111  : o_taken = ~w_ltu;     // BGEU
                default : o_taken = 1'b0;
        endcase
end

endmodule
