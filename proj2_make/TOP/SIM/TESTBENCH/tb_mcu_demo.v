`timescale 1ns/1ps
// Demo TB for mcu_top / mcu_chip_top running SIM/PROG/d01_demo (UART console).
//   The TB is the board : a host terminal on the UART pins, 3 switches and a
//   button on GPIO_IN, LEDs on GPIO_OUT.
//   - host terminal : 8N1, bit = 16 * (BAUDDIV + 1) clk_uart cycles (BAUDDIV = 1
//     in the firmware), counted on clk_uart so the host is exact
//   - script : wait for the prompt "> ", type a command + CR ; before "stat"
//     the button (GPIO_IN[3]) is pressed once
//   - every received character goes to stdout and to +CONSOLE=<file>
//
//   D1 o_halt rises and the TEST pass flag is 1 (firmware got "exit", no bad trap)
//   D2 GPIO_OUT = 4'ha at the end ("led a")
//   D3 no framing error on the host receiver, all 6 commands sent
//   D4 (+GOLD=<file>) console is byte-identical to the golden console
//      (gate-level runs are compared with the RTL console this way)
//
//   -define CHIP : DUT = mcu_chip_top (add -define NO_PAD for RTL without the PAD library)
//   -define GLS  : P&R netlist ; the pass flag comes from gls_pass.vh (`GLS_PASS)
//   plusargs : +CONSOLE=<file> [+GOLD=<file>] [+DUMP]
module tb_mcu_demo;

localparam BAUDDIV  = 1;
localparam BITCLK   = 16 * (BAUDDIV + 1);   // clk_uart cycles per bit
localparam NCMD     = 6;
localparam CMDW     = 16;                   // characters per command slot
localparam TIMEOUT  = 6_000_000;            // ns

reg             r_clkSys, r_clkUart, r_rst_n;
reg             r_hostTx;
reg     [3:0]   r_gpioIn;
wire            w_uartTx;
wire    [3:0]   w_gpioOut;
wire            w_halt;

`ifdef CHIP
`define MCU_H dut.u_mcu
mcu_chip_top dut (
`else
`define MCU_H dut
mcu_top dut (
`endif
        .i_clkSys       (r_clkSys),
        .i_clkUart      (r_clkUart),
        .i_rst_n        (r_rst_n),
        .i_uartRx       (r_hostTx),
        .o_uartTx       (w_uartTx),
        .i_gpioIn       (r_gpioIn),
        .o_gpioOut      (w_gpioOut),
        .o_halt         (w_halt)
);

`ifdef GLS
`include "gls_pass.vh"
wire            w_pass = `GLS_PASS;
`else
wire            w_pass = `MCU_H.u_test.o_pass;
`endif

initial begin r_clkSys  = 1'b0; forever #5    r_clkSys  = ~r_clkSys;  end
initial begin r_clkUart = 1'b0; forever #9.7  r_clkUart = ~r_clkUart; end

// ---------------- console (host receiver) ----------------
reg     [8*200-1:0] r_conFile, r_goldFile;
integer         r_fdCon, r_fdGold, r_nChar, r_frameErr, r_goldErr, r_goldPos;
reg     [7:0]   r_rxByte, r_prev;
reg             r_rxOn, r_prompt;
integer         i, k;

// TB inputs change on the falling edge of their clock : the DUT samples on the
// rising edge, so no simulator ordering race (and no race against the clock
// tree / PAD delay in GLS)
task automatic wait_uclk_n;
        input integer n;
        integer j;
        begin
                for (j = 0; j < n; j = j + 1) @(negedge r_clkUart);
        end
endtask

task automatic wait_uclk;
        input integer n;
        integer j;
        begin
                for (j = 0; j < n; j = j + 1) @(posedge r_clkUart);
        end
endtask

task got_char;
        input [7:0] c;
        integer g;
        begin
                $write("%c", c);
                if (r_fdCon) $fwrite(r_fdCon, "%c", c);
                if (r_fdGold) begin
                        g = $fgetc(r_fdGold);
                        if (g != c) begin
                                if (r_goldErr == 0)
                                        $display("\n[D4] first console difference at byte %0d : got %02h, golden %02h",
                                                 r_goldPos, c, g[7:0]);
                                r_goldErr = r_goldErr + 1;
                        end
                        r_goldPos = r_goldPos + 1;
                end
                if (r_prev == ">" && c == " ") r_prompt = 1'b1;
                r_prev  = c;
                r_nChar = r_nChar + 1;
        end
endtask

// start bit -> middle of each bit -> stop bit
always @(negedge w_uartTx) begin
        if (r_rxOn) begin
                wait_uclk(BITCLK / 2);
                if (w_uartTx == 1'b0) begin
                        for (k = 0; k < 8; k = k + 1) begin
                                wait_uclk(BITCLK);
                                r_rxByte[k] = w_uartTx;
                        end
                        wait_uclk(BITCLK);
                        if (w_uartTx !== 1'b1) r_frameErr = r_frameErr + 1;
                        got_char(r_rxByte);
                end
        end
end

// ---------------- host transmitter ----------------
task send_byte;
        input [7:0] b;
        integer j;
        begin
                @(negedge r_clkUart);
                r_hostTx = 1'b0;
                wait_uclk_n(BITCLK);
                for (j = 0; j < 8; j = j + 1) begin
                        r_hostTx = b[j];
                        wait_uclk_n(BITCLK);
                end
                r_hostTx = 1'b1;
                wait_uclk_n(BITCLK);
        end
endtask

reg     [8*CMDW-1:0] r_cmd [0:NCMD-1];
integer         r_sent;

task send_cmd;
        input [8*CMDW-1:0] s;
        integer j;
        begin
                for (j = CMDW - 1; j >= 0; j = j - 1)
                        if (s[8*j +: 8] != 8'd0) send_byte(s[8*j +: 8]);
                send_byte(8'h0D);
        end
endtask

task press_button;
        begin
                @(negedge r_clkSys);
                r_gpioIn[3] = 1'b1;
                repeat (100) @(negedge r_clkSys);
                r_gpioIn[3] = 1'b0;
                repeat (100) @(negedge r_clkSys);
        end
endtask

// ---------------- main ----------------
integer         r_cycles, r_haltCycle;
always @(posedge r_clkSys) if (r_rst_n) r_cycles <= r_cycles + 1;

initial begin
        r_cmd[0] = "help";
        r_cmd[1] = "led a";
        r_cmd[2] = "sw";
        r_cmd[3] = "hello";
        r_cmd[4] = "stat";
        r_cmd[5] = "exit";

        r_fdCon = 0; r_fdGold = 0;
        if ($value$plusargs("CONSOLE=%s", r_conFile)) r_fdCon  = $fopen(r_conFile, "w");
        if ($value$plusargs("GOLD=%s", r_goldFile)) begin
                r_fdGold = $fopen(r_goldFile, "r");
                if (!r_fdGold) $display("[D4] cannot open golden console");
        end
        if ($test$plusargs("DUMP")) begin
                $dumpfile("tb_mcu_demo.vcd");
                $dumpvars(0, tb_mcu_demo);
        end

        r_nChar = 0; r_frameErr = 0; r_goldErr = 0; r_goldPos = 0;
        r_prev = 8'd0; r_prompt = 1'b0; r_rxOn = 1'b0; r_sent = 0;
        r_cycles = 0; r_haltCycle = -1;
        r_hostTx = 1'b1;
        r_gpioIn = 4'b0101;                     // switches = 5, button released
        r_rst_n  = 1'b0;
        repeat (10) @(negedge r_clkSys);
        r_rst_n = 1'b1;
        repeat (20) @(posedge r_clkSys);
        r_rxOn = 1'b1;

        for (i = 0; i < NCMD; i = i + 1) begin
                wait (r_prompt == 1'b1 || w_halt == 1'b1);
                if (w_halt) i = NCMD;
                else begin
                        r_prompt = 1'b0;
                        if (i == 4) press_button;
                        send_cmd(r_cmd[i]);
                        r_sent = r_sent + 1;
                end
        end
end

always @(posedge w_halt) r_haltCycle = r_cycles;

initial begin : finish
        reg ok;
        while (w_halt !== 1'b1 && $time < TIMEOUT) @(posedge r_clkSys);
        // let the last characters ("bye") reach the host receiver
        wait_uclk(BITCLK * 12);
        ok = 1'b1;
        $display("");
        $display("------------------------------------------------------------");
        if (w_halt === 1'b1 && w_pass === 1'b1)
                $display("PASS: D1 o_halt = 1, TEST pass = 1 (halt@%0d)", r_haltCycle);
        else begin
                $display("FAIL: D1 o_halt = %b, TEST pass = %b (timeout %0d ns)", w_halt, w_pass, TIMEOUT);
                ok = 1'b0;
        end
        if (w_gpioOut === 4'ha) $display("PASS: D2 GPIO_OUT = a");
        else begin $display("FAIL: D2 GPIO_OUT = %h (exp a)", w_gpioOut); ok = 1'b0; end
        if (r_frameErr == 0 && r_sent == NCMD)
                $display("PASS: D3 %0d commands, %0d chars, frame error 0", r_sent, r_nChar);
        else begin
                $display("FAIL: D3 %0d / %0d commands, frame error %0d", r_sent, NCMD, r_frameErr);
                ok = 1'b0;
        end
        if (r_fdGold) begin
                if (r_goldErr == 0 && $fgetc(r_fdGold) == -1)
                        $display("PASS: D4 console == golden (%0d bytes)", r_goldPos);
                else begin
                        $display("FAIL: D4 console differs from golden (%0d bytes differ, %0d compared)", r_goldErr, r_goldPos);
                        ok = 1'b0;
                end
        end
        $display("DEMO %s  chars=%0d halt@%0d", ok ? "ALL PASS" : "FAIL", r_nChar, r_haltCycle);
        if (r_fdCon) $fclose(r_fdCon);
        $finish;
end

endmodule
