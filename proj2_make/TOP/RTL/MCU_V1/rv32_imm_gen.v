`timescale 1ns/1ps
`include "rv32_defs.vh"
// -----------------------------------------------------------------------------
// rv32_imm_gen  (ID stage, combinational)
//   I : inst[31:20]                                   sign-ext
//   S : inst[31:25], inst[11:7]                       sign-ext
//   B : inst[31], inst[7], inst[30:25], inst[11:8], 0 sign-ext
//   U : inst[31:12], 12'b0
//   J : inst[31], inst[19:12], inst[20], inst[30:21], 0 sign-ext
//   Z : CSR zimm inst[19:15]                          zero-ext
// -----------------------------------------------------------------------------
module rv32_imm_gen (
        input   wire    [31:0]  i_inst,
        input   wire    [2:0]   i_immType,

        output  reg     [31:0]  o_imm
);

wire            w_sign = i_inst[31];

always @(*) begin
        case (i_immType)
                `IMM_I  : o_imm = {{20{w_sign}}, i_inst[31:20]};
                `IMM_S  : o_imm = {{20{w_sign}}, i_inst[31:25], i_inst[11:7]};
                `IMM_B  : o_imm = {{19{w_sign}}, i_inst[31], i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
                `IMM_U  : o_imm = {i_inst[31:12], 12'd0};
                `IMM_J  : o_imm = {{11{w_sign}}, i_inst[31], i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};
                `IMM_Z  : o_imm = {27'd0, i_inst[19:15]};
                default : o_imm = 32'd0;
        endcase
end

endmodule
