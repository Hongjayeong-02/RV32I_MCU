`timescale 1ns/1ps
`include "rv32_defs.vh"
// -----------------------------------------------------------------------------
// rv32_alu  (EX stage, combinational)
//   32-bit ALU for RV32I. Shift amount = i_opB[4:0] (RV32I rule).
//   SLT / SLTU share one 33-bit subtractor with SUB:
//     - unsigned a<b : borrow bit (w_sub[32])
//     - signed   a<b : signs differ -> a is negative, else sign of a-b
//   ALU_PASSB returns operand B (LUI : B = U-immediate).
// -----------------------------------------------------------------------------
module rv32_alu (
        input   wire    [3:0]   i_aluOp,
        input   wire    [31:0]  i_opA,
        input   wire    [31:0]  i_opB,

        output  reg     [31:0]  o_result
);

wire    [4:0]   w_shamt = i_opB[4:0];
wire    [32:0]  w_sub   = {1'b0, i_opA} - {1'b0, i_opB};
wire            w_ltu   = w_sub[32];
wire            w_lt    = (i_opA[31] ^ i_opB[31]) ? i_opA[31] : w_sub[31];

always @(*) begin
        case (i_aluOp)
                `ALU_ADD   : o_result = i_opA + i_opB;
                `ALU_SUB   : o_result = w_sub[31:0];
                `ALU_SLL   : o_result = i_opA << w_shamt;
                `ALU_SLT   : o_result = {31'd0, w_lt};
                `ALU_SLTU  : o_result = {31'd0, w_ltu};
                `ALU_XOR   : o_result = i_opA ^ i_opB;
                `ALU_SRL   : o_result = i_opA >> w_shamt;
                `ALU_SRA   : o_result = $signed(i_opA) >>> w_shamt;
                `ALU_OR    : o_result = i_opA | i_opB;
                `ALU_AND   : o_result = i_opA & i_opB;
                `ALU_PASSB : o_result = i_opB;
                default    : o_result = 32'd0;
        endcase
end

endmodule
