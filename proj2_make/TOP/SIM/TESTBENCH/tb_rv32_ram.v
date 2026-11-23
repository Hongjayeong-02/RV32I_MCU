`timescale 1ns/1ps
// Self-checking TB for rv32_ram.
//   M1 word write / read on every address (address-unique pattern)
//   M2 single-byte writes : only the enabled lane changes, neighbours intact
//   M3 halfword write (upper lanes)
//   M4 be = 0000 writes nothing
//   ADDR_W is a parameter : run with -defparam tb_rv32_ram.ADDR_W=6/8/9
module tb_rv32_ram;

parameter ADDR_W = 8;
localparam DEPTH = (1 << ADDR_W);

reg                     r_clk;
reg     [3:0]           r_be;
reg     [ADDR_W-1:0]    r_addr;
reg     [31:0]          r_wdata;
wire    [31:0]          w_rdata;

integer                 r_errCnt, r_phaseErr, i, b;
reg     [31:0]          r_exp;

rv32_ram #(.ADDR_W(ADDR_W)) dut (
        .i_clk          (r_clk),
        .i_be           (r_be),
        .i_addr         (r_addr),
        .i_wdata        (r_wdata),
        .o_rdata        (w_rdata)
);

initial begin r_clk = 1'b0; forever #5 r_clk = ~r_clk; end

function [31:0] pat;
        input   integer a;
        begin
                pat = {a[7:0] ^ 8'hA5, a[7:0], ~a[7:0], a[7:0] ^ 8'h3C};
        end
endfunction

task wr;
        input   [ADDR_W-1:0]    a;
        input   [3:0]           be;
        input   [31:0]          d;
        begin
                @(negedge r_clk); r_addr = a; r_be = be; r_wdata = d;
                @(negedge r_clk); r_be = 4'b0000;
        end
endtask

task rd_chk;
        input   [ADDR_W-1:0]    a;
        input   [31:0]          e;
        begin
                @(negedge r_clk); r_addr = a; r_be = 4'b0000;
                #1;
                if (w_rdata !== e) begin
                        if (r_phaseErr < 3) $display("  mismatch addr=%0d exp=%08h got=%08h", a, e, w_rdata);
                        r_phaseErr = r_phaseErr + 1;
                end
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
        $dumpfile("tb_rv32_ram.vcd");
        $dumpvars(0, tb_rv32_ram);
        r_errCnt = 0; r_phaseErr = 0; r_be = 0; r_addr = 0; r_wdata = 0;

        // M1
        for (i = 0; i < DEPTH; i = i + 1) wr(i, 4'b1111, pat(i));
        for (i = 0; i < DEPTH; i = i + 1) rd_chk(i, pat(i));
        check("M1 word write/read, all addresses");

        // M2 : lanes 0..3 of address 3 set to FF one by one
        r_exp = pat(3);
        for (b = 0; b < 4; b = b + 1) begin
                wr(3, 4'b0001 << b, 32'hFFFF_FFFF);
                r_exp = r_exp | (32'hFF << (8 * b));
                rd_chk(3, r_exp);
        end
        rd_chk(2, pat(2));
        rd_chk(4, pat(4));
        check("M2 byte writes : enabled lane only, neighbours intact");

        // M3
        wr(5, 4'b1100, 32'h1234_5678);
        r_exp = pat(5); r_exp[31:16] = 16'h1234;
        rd_chk(5, r_exp);
        check("M3 halfword write (be=1100)");

        // M4
        wr(6, 4'b0000, 32'hDEAD_BEEF);
        rd_chk(6, pat(6));
        check("M4 be=0000 writes nothing");

        if (r_errCnt == 0) $display("RAM ALL PASS  ADDR_W=%0d (%0d B)", ADDR_W, DEPTH * 4);
        else               $display("RAM FAIL  errors=%0d", r_errCnt);
        $finish;
end

endmodule
