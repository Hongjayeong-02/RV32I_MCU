`timescale 1ns/1ps
`include "rv32_defs.vh"
// Self-checking TB for rv32_imm_gen.
//   I1 every immediate type (I/S/B/U/J/Z) incl. min / max offsets
//   Vectors: SIM/TESTBENCH/imm_vectors.vh (TOOLS/gen_imm_vectors.py)
//     - instruction words from GNU as, expected value from the asm TEXT
//       (e.g. "beq .-4096" -> -4096), so the bit shuffling is checked
//       against the assembler, not against itself.
module tb_rv32_imm_gen;

reg     [31:0]  r_inst;
reg     [2:0]   r_immType;
wire    [31:0]  w_imm;

integer         r_errCnt, r_vecCnt;

rv32_imm_gen dut (.i_inst(r_inst), .i_immType(r_immType), .o_imm(w_imm));

task chk_vec;
        input   [31:0]          inst;
        input   [2:0]           immType;
        input   [31:0]          expV;
        input   [8*40-1:0]      name;
        begin
                r_inst = inst; r_immType = immType;
                #1;
                r_vecCnt = r_vecCnt + 1;
                if (w_imm === expV) begin
                        $display("PASS: %0s -> %08h", name, w_imm);
                end else begin
                        $display("FAIL: %0s  exp=%08h got=%08h", name, expV, w_imm);
                        r_errCnt = r_errCnt + 1;
                end
        end
endtask

initial begin
        $dumpfile("tb_rv32_imm_gen.vcd");
        $dumpvars(0, tb_rv32_imm_gen);
        r_errCnt = 0; r_vecCnt = 0;
        r_inst = 32'd0; r_immType = 3'd0;
        #1;

`include "imm_vectors.vh"

        if (r_errCnt == 0) $display("IMM_GEN ALL PASS  vectors=%0d", r_vecCnt);
        else               $display("IMM_GEN FAIL  errors=%0d / %0d", r_errCnt, r_vecCnt);
        $finish;
end

endmodule
