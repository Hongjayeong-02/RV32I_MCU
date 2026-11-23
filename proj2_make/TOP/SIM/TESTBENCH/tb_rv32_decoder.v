`timescale 1ns/1ps
`include "rv32_defs.vh"
// Self-checking TB for rv32_decoder.
//   D1 all 47 legal instructions (+ rd=x0 / rs1=x0 / zimm=0 variants)
//   D2 14 illegal encodings : o_illegal=1 and every side effect 0
//   Vectors: SIM/TESTBENCH/dec_vectors.vh (TOOLS/gen_dec_vectors.py)
//     - instruction words come from GNU as (not hand-encoded)
//     - expected controls come from an independent Python model of spec 4/5/6
//     - illegal vectors compare only the side-effect bits (mask)
module tb_rv32_decoder;

reg     [31:0]  r_inst;

wire    [3:0]   w_aluOp;
wire    [1:0]   w_aSrc;
wire            w_bSrc;
wire    [2:0]   w_immType;
wire            w_useRs1, w_useRs2;
wire            w_regWrite;
wire    [1:0]   w_wbSel;
wire            w_memRead, w_memWrite;
wire    [1:0]   w_memSize;
wire            w_memUnsigned;
wire            w_branch, w_jal, w_jalr;
wire            w_csr;
wire    [1:0]   w_csrCmd;
wire            w_csrRe, w_csrWe;
wire            w_ecall, w_ebreak, w_mret, w_illegal;
wire    [4:0]   w_rd, w_rs1, w_rs2;
wire    [2:0]   w_funct3;
wire    [11:0]  w_csrAddr;

integer         r_errCnt, r_vecCnt;

rv32_decoder dut (
        .i_inst         (r_inst),
        .o_aluOp        (w_aluOp),
        .o_aSrc         (w_aSrc),
        .o_bSrc         (w_bSrc),
        .o_immType      (w_immType),
        .o_useRs1       (w_useRs1),
        .o_useRs2       (w_useRs2),
        .o_regWrite     (w_regWrite),
        .o_wbSel        (w_wbSel),
        .o_memRead      (w_memRead),
        .o_memWrite     (w_memWrite),
        .o_memSize      (w_memSize),
        .o_memUnsigned  (w_memUnsigned),
        .o_branch       (w_branch),
        .o_jal          (w_jal),
        .o_jalr         (w_jalr),
        .o_csr          (w_csr),
        .o_csrCmd       (w_csrCmd),
        .o_csrRe        (w_csrRe),
        .o_csrWe        (w_csrWe),
        .o_ecall        (w_ecall),
        .o_ebreak       (w_ebreak),
        .o_mret         (w_mret),
        .o_illegal      (w_illegal),
        .o_rd           (w_rd),
        .o_rs1          (w_rs1),
        .o_rs2          (w_rs2),
        .o_funct3       (w_funct3),
        .o_csrAddr      (w_csrAddr)
);

// same packing as TOOLS/gen_dec_vectors.py
wire    [26:0]  w_got = {w_illegal, w_ecall, w_ebreak, w_mret, w_csr, w_csrRe, w_csrWe,
                         w_branch, w_jal, w_jalr, w_memRead, w_memWrite, w_regWrite,
                         w_wbSel, w_useRs1, w_useRs2, w_aSrc, w_bSrc, w_immType, w_aluOp};

task chk_vec;
        input   [31:0]          inst;
        input   [26:0]          expV;
        input   [26:0]          mask;
        input   [8*40-1:0]      name;
        begin
                r_inst = inst;
                #1;
                r_vecCnt = r_vecCnt + 1;
                if ((w_got & mask) === (expV & mask)) begin
                        $display("PASS: %08h %0s", inst, name);
                end else begin
                        $display("FAIL: %08h %0s  exp=%07h got=%07h diff=%07h", inst, name,
                                 expV & mask, w_got & mask, (expV ^ w_got) & mask);
                        r_errCnt = r_errCnt + 1;
                end
        end
endtask

initial begin
        $dumpfile("tb_rv32_decoder.vcd");
        $dumpvars(0, tb_rv32_decoder);
        r_errCnt = 0; r_vecCnt = 0;
        r_inst   = 32'h0000_0013;                       // NOP
        #1;

`include "dec_vectors.vh"

        if (r_errCnt == 0) $display("DECODER ALL PASS  vectors=%0d", r_vecCnt);
        else               $display("DECODER FAIL  errors=%0d / %0d", r_errCnt, r_vecCnt);
        $finish;
end

endmodule
