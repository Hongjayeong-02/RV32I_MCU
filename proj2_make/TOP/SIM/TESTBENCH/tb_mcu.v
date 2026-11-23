`timescale 1ns/1ps
// Self-checking TB for mcu_top (SoC level, spec 12).
//   - the program is compiled in : SIM/PROG/<test>/rv32_rom.v (module rv32_rom)
//   - clk_sys 10 ns, clk_uart ~19.4 ns (asynchronous to clk_sys)
//   - board : GPIO loopback (gpio_in = gpio_out), UART loopback (rx = tx)
//   - the commit port of the core is watched through the hierarchy
//
//   mode 1 (+HEX=expected.hex) : every commit is compared with the ISS record
//            (programs whose behaviour the ISS can predict : M1 / M2 tests)
//   mode 2 (+TRACE only)      : the RTL trace and an event log are written ;
//            TOOLS/check_replay.py replays the ISS with the RTL interrupt points
//            and MMIO read values and compares the rest (M3 peripheral tests)
//   -define CHIP : DUT = mcu_chip_top (add -define NO_PAD for RTL without the PAD library)
//   plusargs : +TEST=<name> [+HEX=<file>] [+TRACE=<file>] [+EVENTS=<file>] [+DUMP]
//   S1 commit trace == ISS (mode 1 only)
//   S2 TEST_STATUS = PASS and o_halt = 1
//
//   -define GLS (post-route gate-level, SIM/GLS/run_gls.sh) : the netlist is flat
//   and the commit port is gone, so the TB only uses pins + one netlist flop :
//     G1 o_halt rises            G2 TEST pass flop (`GLS_PASS, from gls_pass.vh) = 1
//     halt cycle is printed and compared with the RTL run by the script
module tb_mcu;

localparam MAXW = 8 * 20000;

reg             r_clkSys, r_clkUart, r_rst_n;
wire            w_uartTx;
wire    [3:0]   w_gpioOut;
wire            w_halt;

reg     [31:0]  r_exp [0:MAXW-1];
reg     [8*200-1:0] r_hexFile, r_testName, r_traceFile, r_evFile;
reg             r_hexMode;
integer         r_fd, r_fdEv, r_idx, r_commits, r_cycles, r_errCnt, r_mmErr, r_traps, r_ints, r_apbCnt;

`ifdef CHIP
// chip level (M5) : PAD ring around mcu_top, core signals one level down
`define MCU_H dut.u_mcu
mcu_chip_top dut (
`else
`define MCU_H dut
mcu_top dut (
`endif
        .i_clkSys       (r_clkSys),
        .i_clkUart      (r_clkUart),
        .i_rst_n        (r_rst_n),
        .i_uartRx       (w_uartTx),
        .o_uartTx       (w_uartTx),
        .i_gpioIn       (w_gpioOut),
        .o_gpioOut      (w_gpioOut),
        .o_halt         (w_halt)
);

// ---------------- core commit port (hierarchical) ----------------
`ifdef GLS
`include "gls_pass.vh"
wire            w_cmtValid  = 1'b0;
wire    [31:0]  w_cmtPc     = 32'd0;
wire    [31:0]  w_cmtInst   = 32'd0;
wire            w_cmtRdWe   = 1'b0;
wire    [4:0]   w_cmtRd     = 5'd0;
wire    [31:0]  w_cmtRdVal  = 32'd0;
wire            w_cmtStWe   = 1'b0;
wire    [1:0]   w_cmtStSize = 2'd0;
wire    [31:0]  w_cmtStAddr = 32'd0;
wire    [31:0]  w_cmtStData = 32'd0;
wire            w_trapValid = 1'b0;
wire    [31:0]  w_trapCause = 32'd0;
wire    [31:0]  w_trapPc    = 32'd0;
wire            w_pass      = `GLS_PASS;
wire            w_apbDone   = 1'b0;
`else
wire            w_cmtValid  = `MCU_H.u_core.o_cmtValid;
wire    [31:0]  w_cmtPc     = `MCU_H.u_core.o_cmtPc;
wire    [31:0]  w_cmtInst   = `MCU_H.u_core.o_cmtInst;
wire            w_cmtRdWe   = `MCU_H.u_core.o_cmtRdWe;
wire    [4:0]   w_cmtRd     = `MCU_H.u_core.o_cmtRd;
wire    [31:0]  w_cmtRdVal  = `MCU_H.u_core.o_cmtRdVal;
wire            w_cmtStWe   = `MCU_H.u_core.o_cmtStWe;
wire    [1:0]   w_cmtStSize = `MCU_H.u_core.o_cmtStSize;
wire    [31:0]  w_cmtStAddr = `MCU_H.u_core.o_cmtStAddr;
wire    [31:0]  w_cmtStData = `MCU_H.u_core.o_cmtStData;
wire            w_trapValid = `MCU_H.u_core.o_trapValid;
wire    [31:0]  w_trapCause = `MCU_H.u_core.o_trapCause;
wire    [31:0]  w_trapPc    = `MCU_H.u_core.o_trapPc;
wire            w_pass      = `MCU_H.u_test.o_pass;
wire            w_apbDone   = `MCU_H.u_bridge.o_done;
`endif

initial begin r_clkSys  = 1'b0; forever #5    r_clkSys  = ~r_clkSys;  end
initial begin r_clkUart = 1'b0; forever #9.7  r_clkUart = ~r_clkUart; end

// ---------------- trace / event log ----------------
task write_trace;
        begin
                if (r_fd) begin
                        $fwrite(r_fd, "%08h %08h", w_cmtPc, w_cmtInst);
                        if (w_cmtRdWe && r_hexMode && r_exp[r_idx + 2][9])
                                $fwrite(r_fd, " x%02d=--------", w_cmtRd);
                        else if (w_cmtRdWe)
                                $fwrite(r_fd, " x%02d=%08h", w_cmtRd, w_cmtRdVal);
                        if (w_cmtStWe && r_hexMode && r_exp[r_idx + 4][9])
                                $fwrite(r_fd, " M[%08h]<=%0s", w_cmtStAddr,
                                        (w_cmtStSize == 2'd0) ? "--" : (w_cmtStSize == 2'd1) ? "----" : "--------");
                        else if (w_cmtStWe) begin
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

// event log for replay : C = commit (with its rd value), T = trap
//   "C <pc> <rdWe> <rdVal>" lets the checker take MMIO / mcycle read values
//   "T <pc> <cause>" is where the RTL took a trap (interrupts are replayed there)
always @(posedge r_clkSys) begin
        if (r_rst_n && r_fdEv) begin
                // same cycle : the WB commit is older than the MEM trap -> C first
                if (w_cmtValid)  $fwrite(r_fdEv, "C %08h %0d %08h\n", w_cmtPc, w_cmtRdWe, w_cmtRdVal);
                if (w_trapValid) $fwrite(r_fdEv, "T %08h %08h\n", w_trapPc, w_trapCause);
        end
end

// ---------------- compare ----------------
task fail_line;
        input   [8*40-1:0]      what;
        input   [31:0]          expV, gotV;
        begin
                if (r_mmErr < 5)
                        $display("  mismatch #%0d pc=%08h %0s exp=%08h got=%08h", r_commits, w_cmtPc, what, expV, gotV);
                r_mmErr = r_mmErr + 1;
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
                if (r_hexMode)
                        check(r_mmErr == 0 && r_exp[r_idx] == 32'hffff_ffff, "S1 commit trace == ISS (pc, inst, rd, store)");
`ifdef GLS
                check(w_halt,           "G1 o_halt = 1");
                check(w_pass === 1'b1,  "G2 TEST pass flop = 1 (netlist)");
`else
                check(w_halt && w_pass, "S2 TEST_STATUS = PASS, o_halt = 1");
`endif
`ifdef GLS
                if (r_errCnt == 0)
                        $display("MCU %0s ALL PASS  gls halt@%0d", r_testName, r_haltCycle);
`else
                if (r_errCnt == 0)
                        $display("MCU %0s ALL PASS  commits=%0d cycles=%0d CPI=%0d.%02d traps=%0d(int %0d) apb=%0d mode=%0s halt@%0d",
                                 r_testName, r_commits, r_cycles, r_cycles / r_commits, (r_cycles * 100 / r_commits) % 100,
                                 r_traps, r_ints, r_apbCnt, r_hexMode ? "hex" : "replay", r_haltCycle);
`endif
                else
                        $display("MCU %0s FAIL  errors=%0d mismatches=%0d commits=%0d", r_testName, r_errCnt, r_mmErr, r_commits);
                if (r_fd)   $fclose(r_fd);
                if (r_fdEv) $fclose(r_fdEv);
                $finish;
        end
endtask

reg             r_endPending;
integer         r_endWait;
integer         r_haltCycle;
reg             r_haltSeen;

always @(posedge r_clkSys) begin
        if (r_rst_n) begin
                r_cycles = r_cycles + 1;
                if (w_apbDone) r_apbCnt = r_apbCnt + 1;
                if (w_trapValid) begin
                        r_traps = r_traps + 1;
                        if (w_trapCause[31]) r_ints = r_ints + 1;
                end
                // after the TEST_STATUS store has committed, the program only spins : ignore
                if (w_cmtValid && !r_endPending) begin
                        write_trace;
                        if (r_hexMode) begin
                                if (r_exp[r_idx] == 32'hffff_ffff) begin
                                        fail_line("extra commit after end", 32'hffff_ffff, w_cmtPc);
                                end else begin
                                        if (w_cmtPc   !== r_exp[r_idx])     fail_line("pc",   r_exp[r_idx],     w_cmtPc);
                                        if (w_cmtInst !== r_exp[r_idx + 1]) fail_line("inst", r_exp[r_idx + 1], w_cmtInst);
                                        if ({w_cmtRdWe, 3'd0, (w_cmtRdWe ? w_cmtRd : 5'd0)} !== r_exp[r_idx + 2][8:0])
                                                fail_line("rdWe/rd", r_exp[r_idx + 2], {23'd0, w_cmtRdWe, 3'd0, w_cmtRd});
                                        if (w_cmtRdWe && !r_exp[r_idx + 2][9] && w_cmtRdVal !== r_exp[r_idx + 3])
                                                fail_line("rdVal", r_exp[r_idx + 3], w_cmtRdVal);
                                        if (w_cmtStWe !== r_exp[r_idx + 4][8]) fail_line("stWe", r_exp[r_idx + 4], {31'd0, w_cmtStWe});
                                        if (w_cmtStWe && (w_cmtStAddr !== r_exp[r_idx + 5] ||
                                                          (!r_exp[r_idx + 4][9] && w_cmtStData !== r_exp[r_idx + 6])))
                                                fail_line("store", r_exp[r_idx + 6], w_cmtStData);
                                        r_idx = r_idx + 8;
                                end
                        end
                        r_commits = r_commits + 1;
                        // the store to TEST_STATUS has committed : o_halt is set one cycle later
                        if (w_cmtStWe && w_cmtStAddr == 32'h4000_3000) begin r_endPending = 1'b1; r_endWait = 0; end
                        if (r_mmErr >= 20) finish_test;
                end
                if (w_halt && !r_haltSeen) begin
                        r_haltSeen  = 1'b1;
                        r_haltCycle = r_cycles;
`ifdef GLS
                        r_endPending = 1'b1; r_endWait = 0;     // no commit port : end on the pin
`endif
                end
                if (r_endPending) begin
                        r_endWait = r_endWait + 1;
                        if (r_endWait > 2) finish_test;
                end
                if (r_cycles > 200000) begin
                        $display("  timeout after %0d cycles, %0d commits", r_cycles, r_commits);
                        finish_test;
                end
        end
end

// ---------------- start ----------------
initial begin
        r_idx = 0; r_commits = 0; r_cycles = 0; r_errCnt = 0; r_mmErr = 0; r_traps = 0; r_ints = 0; r_apbCnt = 0;
        r_fd = 0; r_fdEv = 0; r_endPending = 1'b0; r_endWait = 0; r_haltCycle = 0; r_haltSeen = 1'b0;
        if (!$value$plusargs("TEST=%s", r_testName)) r_testName = "?";
        r_hexMode = $value$plusargs("HEX=%s", r_hexFile);
        if (r_hexMode) $readmemh(r_hexFile, r_exp);
        if ($value$plusargs("TRACE=%s", r_traceFile))  r_fd   = $fopen(r_traceFile, "w");
        if ($value$plusargs("EVENTS=%s", r_evFile))    r_fdEv = $fopen(r_evFile, "w");
        if ($test$plusargs("DUMP")) begin
                $dumpfile("tb_mcu.vcd");
                $dumpvars(0, tb_mcu);
        end
        r_rst_n = 1'b0;
        repeat (4) @(posedge r_clkSys);
        @(negedge r_clkSys) r_rst_n = 1'b1;
end

endmodule
