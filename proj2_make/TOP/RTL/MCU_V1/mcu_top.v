`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_top : RV32I MCU core-level top (no PADs ; the PAD ring is added in M5)
//
//   rv32_core ─ IF ──────────────── rv32_rom port A        (4 KB, case ROM)
//             └ MEM ─ mcu_dbus ─┬── rv32_rom port B
//                               ├── rv32_ram               (1 KB FF array)
//                               └── mcu_apb_bridge ─ APB3 ─┬ uart_v4_apb  0x4000_0000
//                                                          ├ mcu_gpio     0x4000_1000
//                                                          ├ mcu_timer    0x4000_2000
//                                                          └ mcu_test     0x4000_3000
//   interrupts : MEIP = UART | GPIO | TEST_IRQ[0] ; MTIP = timer | TEST_IRQ[1]
//   clocks     : i_clkSys (core, bus, peripherals, UART PCLK), i_clkUart (UART baud side)
//   reset      : i_rst_n asynchronous ; one synchronizer per domain
//                (clk_sys here, the UART has its own two inside)
// -----------------------------------------------------------------------------
module mcu_top (
        input   wire            i_clkSys,
        input   wire            i_clkUart,
        input   wire            i_rst_n,

        input   wire            i_uartRx,
        output  wire            o_uartTx,
        input   wire    [3:0]   i_gpioIn,
        output  wire    [3:0]   o_gpioOut,
        output  wire            o_halt
);

wire            w_rst_n;

uart_v4_rst_sync u_rst_sys (.i_clk(i_clkSys), .i_rst_n(i_rst_n), .o_rst_n(w_rst_n));

// ---------------- core ----------------
wire    [31:0]  w_imemAddr, w_imemData;
wire            w_dReq, w_dWe;
wire    [31:0]  w_dAddr, w_dWdata, w_dRdata;
wire    [3:0]   w_dBe;
wire            w_dReady, w_dErr;
wire            w_irqExt, w_irqTimer;

rv32_core u_core (
        .i_clk          (i_clkSys),
        .i_rst_n        (w_rst_n),
        .o_imemAddr     (w_imemAddr),
        .i_imemData     (w_imemData),
        .o_dmemReq      (w_dReq),
        .o_dmemWe       (w_dWe),
        .o_dmemAddr     (w_dAddr),
        .o_dmemBe       (w_dBe),
        .o_dmemWdata    (w_dWdata),
        .i_dmemRdata    (w_dRdata),
        .i_dmemReady    (w_dReady),
        .i_dmemErr      (w_dErr),
        .i_irqExt       (w_irqExt),
        .i_irqTimer     (w_irqTimer),
        .o_cmtValid     (),
        .o_cmtPc        (),
        .o_cmtInst      (),
        .o_cmtRdWe      (),
        .o_cmtRd        (),
        .o_cmtRdVal     (),
        .o_cmtStWe      (),
        .o_cmtStSize    (),
        .o_cmtStAddr    (),
        .o_cmtStData    (),
        .o_trapValid    (),
        .o_trapCause    (),
        .o_trapPc       ()
);

// ---------------- memories ----------------
wire    [31:0]  w_romB, w_ramRd;
wire    [3:0]   w_ramBe;

rv32_rom u_rom (
        .i_addrA        (w_imemAddr[11:0]),
        .o_dataA        (w_imemData),
        .i_addrB        (w_dAddr[11:0]),
        .o_dataB        (w_romB)
);

rv32_ram #(.ADDR_W(8)) u_ram (
        .i_clk          (i_clkSys),
        .i_be           (w_ramBe),
        .i_addr         (w_dAddr[9:2]),
        .i_wdata        (w_dWdata),
        .o_rdata        (w_ramRd)
);

// ---------------- data bus ----------------
wire            w_apbReq, w_apbDone, w_apbErr;
wire    [31:0]  w_apbRdata;

mcu_dbus u_dbus (
        .i_req          (w_dReq),
        .i_we           (w_dWe),
        .i_addr         (w_dAddr),
        .i_be           (w_dBe),
        .o_rdata        (w_dRdata),
        .o_ready        (w_dReady),
        .o_err          (w_dErr),
        .i_romData      (w_romB),
        .o_ramBe        (w_ramBe),
        .i_ramData      (w_ramRd),
        .o_apbReq       (w_apbReq),
        .i_apbDone      (w_apbDone),
        .i_apbRdata     (w_apbRdata),
        .i_apbErr       (w_apbErr)
);

// ---------------- APB ----------------
wire    [11:0]  w_paddr;
wire            w_pwrite, w_penable;
wire    [31:0]  w_pwdata;
wire    [3:0]   w_psel;
wire    [31:0]  w_prdUart, w_prdGpio, w_prdTimer, w_prdTest;
wire    [3:0]   w_pready, w_pslverr;

mcu_apb_bridge u_bridge (
        .i_clk          (i_clkSys),
        .i_rst_n        (w_rst_n),
        .i_req          (w_apbReq),
        .i_we           (w_dWe),
        .i_addr         (w_dAddr),
        .i_wdata        (w_dWdata),
        .o_done         (w_apbDone),
        .o_rdata        (w_apbRdata),
        .o_err          (w_apbErr),
        .o_paddr        (w_paddr),
        .o_pwrite       (w_pwrite),
        .o_pwdata       (w_pwdata),
        .o_penable      (w_penable),
        .o_psel         (w_psel),
        .i_prdata       ({w_prdTest, w_prdTimer, w_prdGpio, w_prdUart}),
        .i_pready       (w_pready),
        .i_pslverr      (w_pslverr)
);

wire            w_uartIrq, w_gpioIrq, w_mtip;
wire    [1:0]   w_testIrq;
wire            w_pass;

uart_v4_apb u_uart (
        .i_pclk         (i_clkSys),
        .i_uclk         (i_clkUart),
        .rst_n          (i_rst_n),
        .i_psel         (w_psel[0]),
        .i_penable      (w_penable),
        .i_pwrite       (w_pwrite),
        .i_paddr        (w_paddr[7:0]),
        .i_pwdata       (w_pwdata),
        .o_prdata       (w_prdUart),
        .o_pready       (w_pready[0]),
        .o_pslverr      (w_pslverr[0]),
        .i_uartRx       (i_uartRx),
        .o_uartTx       (o_uartTx),
        .o_irq          (w_uartIrq)
);

mcu_gpio u_gpio (
        .i_clk          (i_clkSys),
        .i_rst_n        (w_rst_n),
        .i_psel         (w_psel[1]),
        .i_penable      (w_penable),
        .i_pwrite       (w_pwrite),
        .i_paddr        (w_paddr),
        .i_pwdata       (w_pwdata),
        .o_prdata       (w_prdGpio),
        .o_pready       (w_pready[1]),
        .o_pslverr      (w_pslverr[1]),
        .i_gpioIn       (i_gpioIn),
        .o_gpioOut      (o_gpioOut),
        .o_irq          (w_gpioIrq)
);

mcu_timer u_timer (
        .i_clk          (i_clkSys),
        .i_rst_n        (w_rst_n),
        .i_psel         (w_psel[2]),
        .i_penable      (w_penable),
        .i_pwrite       (w_pwrite),
        .i_paddr        (w_paddr),
        .i_pwdata       (w_pwdata),
        .o_prdata       (w_prdTimer),
        .o_pready       (w_pready[2]),
        .o_pslverr      (w_pslverr[2]),
        .o_mtip         (w_mtip)
);

mcu_test u_test (
        .i_clk          (i_clkSys),
        .i_rst_n        (w_rst_n),
        .i_psel         (w_psel[3]),
        .i_penable      (w_penable),
        .i_pwrite       (w_pwrite),
        .i_paddr        (w_paddr),
        .i_pwdata       (w_pwdata),
        .o_prdata       (w_prdTest),
        .o_pready       (w_pready[3]),
        .o_pslverr      (w_pslverr[3]),
        .o_halt         (o_halt),
        .o_pass         (w_pass),
        .o_irq          (w_testIrq)
);

assign w_irqExt   = w_uartIrq | w_gpioIrq | w_testIrq[0];
assign w_irqTimer = w_mtip    | w_testIrq[1];

endmodule
