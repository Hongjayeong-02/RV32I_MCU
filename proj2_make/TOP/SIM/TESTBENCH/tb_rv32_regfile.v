`timescale 1ns/1ps
// Self-checking TB for rv32_regfile.
//   R1 reset : all 32 registers read 0
//   R2 write to x0 is ignored (x0 reads 0 on both ports)
//   R3 write-first bypass : WB write + ID read of the same reg in one cycle
//   R4 3000 random cycles vs shadow model (bypass included)
// Inputs change at negedge, read ports checked before the posedge,
// shadow updated at the posedge.
module tb_rv32_regfile;

reg             r_clk, r_rst_n;
reg             r_we;
reg     [4:0]   r_rd, r_rs1, r_rs2;
reg     [31:0]  r_wdata;
wire    [31:0]  w_rs1Val, w_rs2Val;

reg     [31:0]  r_shadow [0:31];
reg     [31:0]  r_e1, r_e2;
integer         r_errCnt, r_phaseErr, r_cycCnt, i;

rv32_regfile dut (
        .i_clk          (r_clk),
        .i_rst_n        (r_rst_n),
        .i_we           (r_we),
        .i_rd           (r_rd),
        .i_wdata        (r_wdata),
        .i_rs1          (r_rs1),
        .i_rs2          (r_rs2),
        .o_rs1Val       (w_rs1Val),
        .o_rs2Val       (w_rs2Val)
);

initial begin r_clk = 1'b0; forever #5 r_clk = ~r_clk; end

function [31:0] exp_rd;
        input   [4:0]   rs;
        begin
                if (rs == 5'd0)                 exp_rd = 32'd0;
                else if (r_we && r_rd == rs)    exp_rd = r_wdata;
                else                            exp_rd = r_shadow[rs];
        end
endfunction

task cyc;
        input           we;
        input   [4:0]   rd;
        input   [31:0]  wd;
        input   [4:0]   rs1, rs2;
        begin
                @(negedge r_clk);
                r_we = we; r_rd = rd; r_wdata = wd; r_rs1 = rs1; r_rs2 = rs2;
                #1;
                r_e1 = exp_rd(rs1); r_e2 = exp_rd(rs2);
                r_cycCnt = r_cycCnt + 1;
                if (w_rs1Val !== r_e1 || w_rs2Val !== r_e2) begin
                        if (r_phaseErr < 3)
                                $display("  mismatch we=%0d rd=%0d wd=%08h rs1=%0d exp=%08h got=%08h rs2=%0d exp=%08h got=%08h",
                                         we, rd, wd, rs1, r_e1, w_rs1Val, rs2, r_e2, w_rs2Val);
                        r_phaseErr = r_phaseErr + 1;
                end
                @(posedge r_clk);
                if (we && rd != 5'd0) r_shadow[rd] = wd;
        end
endtask

task check;
        input   [8*60-1:0]      msg;
        begin
                if (r_phaseErr == 0) $display("PASS: %0s", msg);
                else begin $display("FAIL: %0s  errors=%0d", msg, r_phaseErr); r_errCnt = r_errCnt + 1; end
                r_phaseErr = 0;
        end
endtask

initial begin
        $dumpfile("tb_rv32_regfile.vcd");
        $dumpvars(0, tb_rv32_regfile);
        r_errCnt = 0; r_phaseErr = 0; r_cycCnt = 0;
        for (i = 0; i < 32; i = i + 1) r_shadow[i] = 32'd0;
        r_we = 0; r_rd = 0; r_wdata = 0; r_rs1 = 0; r_rs2 = 0;
        r_rst_n = 1'b0;
        repeat (2) @(posedge r_clk);
        @(negedge r_clk) r_rst_n = 1'b1;

        // R1
        for (i = 0; i < 32; i = i + 1) cyc(0, 0, 0, i, 31 - i);
        check("R1 reset : x0..x31 read 0");

        // R2
        cyc(1, 0, 32'hDEAD_BEEF, 0, 0);
        cyc(0, 0, 32'd0,         0, 0);
        check("R2 write to x0 ignored");

        // R3
        cyc(1, 5,  32'h1234_5678, 5,  6);
        cyc(0, 0,  32'd0,         5,  5);
        cyc(1, 31, 32'hCAFE_F00D, 31, 31);
        check("R3 write-first bypass (same-cycle WB -> ID)");

        // R4
        for (i = 0; i < 3000; i = i + 1)
                cyc($random, $random, $random, $random, $random);
        check("R4 3000 random cycles vs shadow model");

        if (r_errCnt == 0) $display("REGFILE ALL PASS  cycles=%0d", r_cycCnt);
        else               $display("REGFILE FAIL  errors=%0d", r_errCnt);
        $finish;
end

endmodule
