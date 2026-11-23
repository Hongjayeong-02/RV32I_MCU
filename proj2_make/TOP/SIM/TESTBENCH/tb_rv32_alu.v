`timescale 1ns/1ps
`include "rv32_defs.vh"
// Self-checking TB for rv32_alu + rv32_branch.
//   A1 corner operands (0, 1, -1, 0x7FFFFFFF, 0x80000000, 31, 32, 0xAAAA.., 0x5555..)
//      all 10 x 10 pairs, every ALU op and every branch funct3
//   A2 5000 random pairs, every ALU op and every branch funct3
//   Reference model: 33-bit sign extension / 64-bit shift (independent of RTL).
//   One PASS/FAIL line per ALU op and per branch funct3 (errors counted inside).
module tb_rv32_alu;

reg     [3:0]   r_aluOp;
reg     [31:0]  r_a, r_b;
reg     [2:0]   r_funct3;
wire    [31:0]  w_result;
wire            w_taken;

integer         r_errCnt, r_chkCnt, i, j, op, f3;
integer         r_opErr [0:15];
integer         r_brErr [0:7];
reg     [31:0]  r_corner [0:9];
reg     [31:0]  r_expY;
reg             r_expT;

rv32_alu    dut_alu (.i_aluOp(r_aluOp), .i_opA(r_a), .i_opB(r_b), .o_result(w_result));
rv32_branch dut_br  (.i_funct3(r_funct3), .i_rs1Val(r_a), .i_rs2Val(r_b), .o_taken(w_taken));

function slt_ref;
        input   [31:0]  a, b;
        reg signed [32:0] sa, sb;
        begin
                sa = {a[31], a}; sb = {b[31], b};
                slt_ref = (sa < sb);
        end
endfunction

function [31:0] sra_ref;
        input   [31:0]  a;
        input   [4:0]   s;
        reg     [63:0]  ext;
        begin
                ext     = {{32{a[31]}}, a} >> s;
                sra_ref = ext[31:0];
        end
endfunction

function [31:0] alu_ref;
        input   [3:0]   o;
        input   [31:0]  a, b;
        begin
                case (o)
                        `ALU_ADD   : alu_ref = a + b;
                        `ALU_SUB   : alu_ref = a + (~b) + 32'd1;
                        `ALU_SLL   : alu_ref = a << b[4:0];
                        `ALU_SLT   : alu_ref = {31'd0, slt_ref(a, b)};
                        `ALU_SLTU  : alu_ref = {31'd0, (a < b)};
                        `ALU_XOR   : alu_ref = a ^ b;
                        `ALU_SRL   : alu_ref = a >> b[4:0];
                        `ALU_SRA   : alu_ref = sra_ref(a, b[4:0]);
                        `ALU_OR    : alu_ref = a | b;
                        `ALU_AND   : alu_ref = a & b;
                        `ALU_PASSB : alu_ref = b;
                        default    : alu_ref = 32'd0;
                endcase
        end
endfunction

function br_ref;
        input   [2:0]   f;
        input   [31:0]  a, b;
        begin
                case (f)
                        3'b000  : br_ref =  (a == b);
                        3'b001  : br_ref =  (a != b);
                        3'b100  : br_ref =  slt_ref(a, b);
                        3'b101  : br_ref = !slt_ref(a, b);
                        3'b110  : br_ref =  (a < b);
                        3'b111  : br_ref = !(a < b);
                        default : br_ref =  1'b0;
                endcase
        end
endfunction

task run_pair;
        input   [31:0]  a, b;
        begin
                r_a = a; r_b = b;
                for (op = 0; op <= 11; op = op + 1) begin
                        r_aluOp = op; #1;
                        r_expY = alu_ref(op, a, b);
                        r_chkCnt = r_chkCnt + 1;
                        if (w_result !== r_expY) begin
                                if (r_opErr[op] < 3)
                                        $display("  mismatch ALU op=%0d a=%08h b=%08h exp=%08h got=%08h",
                                                 op, a, b, r_expY, w_result);
                                r_opErr[op] = r_opErr[op] + 1;
                        end
                end
                for (f3 = 0; f3 < 8; f3 = f3 + 1) begin
                        r_funct3 = f3; #1;
                        r_expT = br_ref(f3, a, b);
                        r_chkCnt = r_chkCnt + 1;
                        if (w_taken !== r_expT) begin
                                if (r_brErr[f3] < 3)
                                        $display("  mismatch BR f3=%0d a=%08h b=%08h exp=%0d got=%0d",
                                                 f3, a, b, r_expT, w_taken);
                                r_brErr[f3] = r_brErr[f3] + 1;
                        end
                end
        end
endtask

task report;
        input   integer         errs;
        input   [8*40-1:0]      msg;
        begin
                if (errs == 0) $display("PASS: %0s", msg);
                else begin $display("FAIL: %0s  errors=%0d", msg, errs); r_errCnt = r_errCnt + 1; end
        end
endtask

initial begin
        $dumpfile("tb_rv32_alu.vcd");
        $dumpvars(0, tb_rv32_alu);
        r_errCnt = 0; r_chkCnt = 0;
        for (i = 0; i < 16; i = i + 1) r_opErr[i] = 0;
        for (i = 0; i < 8;  i = i + 1) r_brErr[i] = 0;

        r_corner[0] = 32'h0000_0000; r_corner[1] = 32'h0000_0001;
        r_corner[2] = 32'hFFFF_FFFF; r_corner[3] = 32'h7FFF_FFFF;
        r_corner[4] = 32'h8000_0000; r_corner[5] = 32'h8000_0001;
        r_corner[6] = 32'h0000_001F; r_corner[7] = 32'h0000_0020;
        r_corner[8] = 32'hAAAA_AAAA; r_corner[9] = 32'h5555_5555;

        // A1 + A2
        for (i = 0; i < 10; i = i + 1)
                for (j = 0; j < 10; j = j + 1)
                        run_pair(r_corner[i], r_corner[j]);
        for (i = 0; i < 5000; i = i + 1)
                run_pair($random, $random);

        report(r_opErr[`ALU_ADD],   "ALU ADD");
        report(r_opErr[`ALU_SUB],   "ALU SUB");
        report(r_opErr[`ALU_SLL],   "ALU SLL (shamt = b[4:0])");
        report(r_opErr[`ALU_SLT],   "ALU SLT (signed)");
        report(r_opErr[`ALU_SLTU],  "ALU SLTU");
        report(r_opErr[`ALU_XOR],   "ALU XOR");
        report(r_opErr[`ALU_SRL],   "ALU SRL");
        report(r_opErr[`ALU_SRA],   "ALU SRA (sign fill)");
        report(r_opErr[`ALU_OR],    "ALU OR");
        report(r_opErr[`ALU_AND],   "ALU AND");
        report(r_opErr[`ALU_PASSB], "ALU PASSB (LUI)");
        report(r_opErr[11],         "ALU undefined op -> 0");
        report(r_brErr[0],          "BR BEQ");
        report(r_brErr[1],          "BR BNE");
        report(r_brErr[4],          "BR BLT");
        report(r_brErr[5],          "BR BGE");
        report(r_brErr[6],          "BR BLTU");
        report(r_brErr[7],          "BR BGEU");
        report(r_brErr[2] + r_brErr[3], "BR funct3 010/011 -> not taken");

        if (r_errCnt == 0) $display("ALU ALL PASS  checks=%0d", r_chkCnt);
        else               $display("ALU FAIL  errors=%0d", r_errCnt);
        $finish;
end

endmodule
