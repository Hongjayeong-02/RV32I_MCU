`timescale 1ns/1ps
// Self-checking TB for rv32_core (program level, spec 12).
//   - ROM  : SIM/PROG/<test>/rv32_rom.v (compiled in), ports A (IF) / B (MEM)
//   - RAM  : rv32_ram 1 KB @ 0x1000_0000
//   - TEST : 0x4000_3000 STATUS (write -> end of test), 0x4000_3004 RESULT,
//            0x4000_3008 IRQ (bit0 -> i_irqExt, bit1 -> i_irqTimer), readable like mcu_test
//   - bus error (i_dmemErr with ready) : same rules as mcu_dbus / the ISS
//     (unmapped, ROM write, APB offset beyond the device, sub-word APB write)
//   - every retired instruction (commit port) is compared with the ISS record
//     in expected.hex : pc, inst, rd write, store address / data
//   - +WAIT=1 : random 0-3 wait states on every data access (MEM stall path)
//   plusargs : +HEX=<expected.hex> +TEST=<name> [+WAIT=1] [+TRACE=<rtl.trace>]
//   C1 commit trace == ISS (values marked "no compare" = mcycle reads are skipped)
//   C2 TEST_STATUS = 1 (program self-check)
module tb_rv32_core;

localparam MAXW = 8 * 20000;

reg             r_clk, r_rst_n;

wire    [31:0]  w_imemAddr, w_imemData;
wire            w_dReq, w_dWe;
wire    [31:0]  w_dAddr, w_dWdata;
wire    [3:0]   w_dBe;
reg     [31:0]  r_dRdata;
wire            w_dReady;
wire            w_dErr;
reg     [1:0]   r_irq;
wire            w_trapValid;
wire    [31:0]  w_trapCause, w_trapPc;

wire            w_cmtValid, w_cmtRdWe, w_cmtStWe;
wire    [31:0]  w_cmtPc, w_cmtInst, w_cmtRdVal, w_cmtStAddr, w_cmtStData;
wire    [4:0]   w_cmtRd;
wire    [1:0]   w_cmtStSize;

reg     [31:0]  r_exp [0:MAXW-1];
reg     [8*200-1:0] r_hexFile, r_testName, r_traceFile;
integer         r_fd, r_idx, r_commits, r_cycles, r_errCnt, r_mmErr, r_busErr, r_traps, r_ints;
integer         r_waitOn;
reg             r_statusSeen, r_statusPass;

// ---------------- DUT ----------------
rv32_core dut (
        .i_clk          (r_clk),
        .i_rst_n        (r_rst_n),
        .o_imemAddr     (w_imemAddr),
        .i_imemData     (w_imemData),
        .o_dmemReq      (w_dReq),
        .o_dmemWe       (w_dWe),
        .o_dmemAddr     (w_dAddr),
        .o_dmemBe       (w_dBe),
        .o_dmemWdata    (w_dWdata),
        .i_dmemRdata    (r_dRdata),
        .i_dmemReady    (w_dReady),
        .i_dmemErr      (w_dErr),
        .i_irqExt       (r_irq[0]),
        .i_irqTimer     (r_irq[1]),
        .o_cmtValid     (w_cmtValid),
        .o_cmtPc        (w_cmtPc),
        .o_cmtInst      (w_cmtInst),
        .o_cmtRdWe      (w_cmtRdWe),
        .o_cmtRd        (w_cmtRd),
        .o_cmtRdVal     (w_cmtRdVal),
        .o_cmtStWe      (w_cmtStWe),
        .o_cmtStSize    (w_cmtStSize),
        .o_cmtStAddr    (w_cmtStAddr),
        .o_cmtStData    (w_cmtStData),
        .o_trapValid    (w_trapValid),
        .o_trapCause    (w_trapCause),
        .o_trapPc       (w_trapPc)
);

// ---------------- memories ----------------
wire    [31:0]  w_romB, w_ramRd;
wire            w_isRom  = (w_dAddr[31:12] == 20'h00000);
wire            w_isRam  = (w_dAddr[31:10] == 22'h040000);         // 0x1000_0000 - 0x1000_03FF
// APB region : same rules as mcu_dbus (device size, word write only)
wire            w_apbRg  = (w_dAddr[31:14] == 18'h10000);
wire    [11:0]  w_devSz  = (w_dAddr[13:12] == 2'd0) ? 12'h020 : (w_dAddr[13:12] == 2'd1) ? 12'h010 :
                           (w_dAddr[13:12] == 2'd2) ? 12'h014 : 12'h00C;
wire            w_isApb  = w_apbRg & (w_dAddr[11:0] < w_devSz);
wire            w_isTest = w_isApb & (w_dAddr[13:12] == 2'd3);
reg     [31:0]  r_testResult;
wire            w_dDone  = w_dReq & w_dReady;
assign          w_dErr   = !(w_isRom || w_isRam || w_isApb) || (w_isRom && w_dWe) ||
                           (w_isApb && w_dWe && w_dBe != 4'b1111);

rv32_rom u_rom (.i_addrA(w_imemAddr[11:0]), .o_dataA(w_imemData),
                .i_addrB(w_dAddr[11:0]),    .o_dataB(w_romB));

rv32_ram #(.ADDR_W(8)) u_ram (
        .i_clk          (r_clk),
        .i_be           ((w_dDone & w_dWe & w_isRam & ~w_dErr) ? w_dBe : 4'b0000),
        .i_addr         (w_dAddr[9:2]),
        .i_wdata        (w_dWdata),
        .o_rdata        (w_ramRd)
);

always @(*) begin
        if      (w_isRom) r_dRdata = w_romB;
        else if (w_isRam) r_dRdata = w_ramRd;
        else if (w_isTest) case (w_dAddr[3:2])           // like mcu_test
                2'd0    : r_dRdata = {30'd0, r_statusSeen, r_statusPass};
                2'd1    : r_dRdata = r_testResult;
                default : r_dRdata = {30'd0, r_irq};
        endcase
        else              r_dRdata = 32'd0;              // UART / GPIO / TIMER : not modelled here
end

// ---------------- random wait states ----------------
reg             r_busy;
reg     [1:0]   r_cnt, r_nextWait;
assign w_dReady = (r_waitOn == 0) ? 1'b1 : (r_busy ? (r_cnt == 2'd0) : (r_nextWait == 2'd0));

always @(posedge r_clk) begin
        if (!r_rst_n) begin
                r_busy <= 1'b0; r_cnt <= 2'd0; r_nextWait <= 2'd0;
        end else begin
                if (w_dReq && !w_dReady) begin
                        r_busy <= 1'b1;
                        r_cnt  <= r_busy ? r_cnt - 2'd1 : r_nextWait - 2'd1;
                end else begin
                        r_busy <= 1'b0;
                end
                if (!(w_dReq && !w_dReady)) r_nextWait <= $random;
        end
end

// ---------------- TEST device / statistics ----------------
always @(posedge r_clk) begin
        if (!r_rst_n) begin
                r_irq <= 2'b00;
                r_testResult <= 32'd0;
        end else begin
                if (w_dDone && w_dErr) r_busErr = r_busErr + 1;
                if (w_dDone && !w_dErr && w_isTest && w_dWe) begin
                        if (w_dAddr[3:0] == 4'h0) begin
                                r_statusSeen = 1'b1;
                                r_statusPass = w_dWdata[0];
                        end
                        if (w_dAddr[3:0] == 4'h4) r_testResult <= w_dWdata;
                        if (w_dAddr[3:0] == 4'h8) r_irq <= w_dWdata[1:0];
                end
                if (w_trapValid) begin
                        r_traps = r_traps + 1;
                        if (w_trapCause[31]) r_ints = r_ints + 1;
                end
        end
end

// ---------------- commit compare ----------------
task fail_line;
        input   [8*40-1:0]      what;
        input   [31:0]          expV, gotV;
        begin
                if (r_mmErr < 5)
                        $display("  mismatch #%0d pc=%08h %0s exp=%08h got=%08h", r_commits, w_cmtPc, what, expV, gotV);
                r_mmErr = r_mmErr + 1;
        end
endtask

task write_trace;
        begin
                if (r_fd) begin
                        $fwrite(r_fd, "%08h %08h", w_cmtPc, w_cmtInst);
                        // values the ISS cannot know (mcycle) are printed as dashes, like expected.trace
                        if (w_cmtRdWe && r_exp[r_idx + 2][9]) $fwrite(r_fd, " x%02d=--------", w_cmtRd);
                        else if (w_cmtRdWe)                   $fwrite(r_fd, " x%02d=%08h", w_cmtRd, w_cmtRdVal);
                        if (w_cmtStWe && r_exp[r_idx + 4][9]) begin
                                $fwrite(r_fd, " M[%08h]<=%0s", w_cmtStAddr,
                                        (w_cmtStSize == 2'd0) ? "--" : (w_cmtStSize == 2'd1) ? "----" : "--------");
                        end else if (w_cmtStWe) begin
                                case (w_cmtStSize)
                                        2'd0    : $fwrite(r_fd, " M[%08h]<=%02h", w_cmtStAddr, w_cmtStData[7:0]);
                                        2'd1    : $fwrite(r_fd, " M[%08h]<=%04h", w_cmtStAddr, w_cmtStData[15:0]);
                                        default : $fwrite(r_fd, " M[%08h]<=%08h", w_cmtStAddr, w_cmtStData);
                                endcase
                        end
                        $fwrite(r_fd, "\n");
                end
        end
endtask

task check;
        input           cond;
        input   [8*60-1:0] msg;
        begin
                if (cond) $display("PASS: %0s", msg);
                else begin $display("FAIL: %0s", msg); r_errCnt = r_errCnt + 1; end
        end
endtask

task finish_test;
        begin
                check(r_mmErr == 0 && r_exp[r_idx] == 32'hffff_ffff, "C1 commit trace == ISS (pc, inst, rd, store)");
                check(r_statusSeen && r_statusPass, "C2 TEST_STATUS = 1 (program self-check)");
                if (r_errCnt == 0)
                        $display("CORE %0s ALL PASS  commits=%0d cycles=%0d CPI=%0d.%02d traps=%0d(int %0d) busErr=%0d wait=%0d",
                                 r_testName, r_commits, r_cycles, r_cycles / r_commits, (r_cycles * 100 / r_commits) % 100,
                                 r_traps, r_ints, r_busErr, r_waitOn);
                else
                        $display("CORE %0s FAIL  errors=%0d mismatches=%0d commits=%0d", r_testName, r_errCnt, r_mmErr, r_commits);
                if (r_fd) $fclose(r_fd);
                $finish;
        end
endtask

always @(posedge r_clk) begin
        if (r_rst_n) begin
                r_cycles = r_cycles + 1;
                if (w_cmtValid) begin
                        write_trace;
                        if (r_exp[r_idx] == 32'hffff_ffff) begin
                                fail_line("extra commit after end", 32'hffff_ffff, w_cmtPc);
                        end else begin
                                if (w_cmtPc   !== r_exp[r_idx])          fail_line("pc",     r_exp[r_idx],     w_cmtPc);
                                if (w_cmtInst !== r_exp[r_idx + 1])      fail_line("inst",   r_exp[r_idx + 1], w_cmtInst);
                                if ({w_cmtRdWe, 3'd0, (w_cmtRdWe ? w_cmtRd : 5'd0)} !== r_exp[r_idx + 2][8:0])
                                        fail_line("rdWe/rd", r_exp[r_idx + 2], {23'd0, w_cmtRdWe, 3'd0, (w_cmtRdWe ? w_cmtRd : 5'd0)});
                                if (w_cmtRdWe && !r_exp[r_idx + 2][9] && w_cmtRdVal !== r_exp[r_idx + 3])
                                        fail_line("rdVal",  r_exp[r_idx + 3], w_cmtRdVal);
                                if (w_cmtStWe !== r_exp[r_idx + 4][8])   fail_line("stWe",   r_exp[r_idx + 4], {31'd0, w_cmtStWe});
                                if (w_cmtStWe && (w_cmtStAddr !== r_exp[r_idx + 5] ||
                                                  (!r_exp[r_idx + 4][9] && w_cmtStData !== r_exp[r_idx + 6])))
                                        fail_line("store",  r_exp[r_idx + 6], w_cmtStData);
                                r_idx = r_idx + 8;
                        end
                        r_commits = r_commits + 1;
                        // end : the commit that wrote TEST_STATUS
                        if (w_cmtStWe && w_cmtStAddr == 32'h4000_3000) finish_test;
                        if (r_mmErr >= 20) finish_test;
                end
                if (r_cycles > 400000) begin
                        $display("  timeout after %0d cycles, %0d commits", r_cycles, r_commits);
                        finish_test;
                end
        end
end

// ---------------- start ----------------
initial begin r_clk = 1'b0; forever #5 r_clk = ~r_clk; end

initial begin
        r_idx = 0; r_commits = 0; r_cycles = 0; r_errCnt = 0; r_mmErr = 0; r_busErr = 0; r_traps = 0; r_ints = 0;
        r_statusSeen = 1'b0; r_statusPass = 1'b0; r_fd = 0;
        if (!$value$plusargs("HEX=%s", r_hexFile)) begin
                $display("FAIL: +HEX=<expected.hex> missing"); $finish;
        end
        if (!$value$plusargs("TEST=%s", r_testName)) r_testName = "?";
        if (!$value$plusargs("WAIT=%d", r_waitOn))   r_waitOn = 0;
        if ($value$plusargs("TRACE=%s", r_traceFile)) r_fd = $fopen(r_traceFile, "w");
        $readmemh(r_hexFile, r_exp);
        $dumpfile("tb_rv32_core.vcd");
        $dumpvars(0, tb_rv32_core);
        r_rst_n = 1'b0;
        repeat (3) @(posedge r_clk);
        @(negedge r_clk) r_rst_n = 1'b1;
end

endmodule
