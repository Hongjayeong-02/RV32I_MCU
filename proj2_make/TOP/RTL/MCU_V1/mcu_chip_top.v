`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_chip_top : RV32I MCU chip level (M5) - every external port through an I/O PAD
//   input  : PADDI (PAD -> Y)   i_clkSys, i_clkUart, i_rst_n, i_uartRx, i_gpioIn[3:0]
//   output : PADDO (A -> PAD)   o_uartTx, o_gpioOut[3:0], o_halt
//   14 signal PADs. Power / ground PADs, corners and IO fillers are physical only
//   (added from the IO file in P&R), not in this netlist.
//   Same ports as mcu_top, so tb_mcu can drive either (-define CHIP).
//   `define NO_PAD : bypass every PAD (RTL simulation without the PAD library)
// -----------------------------------------------------------------------------
module mcu_chip_top (
        input   wire            i_clkSys,
        input   wire            i_clkUart,
        input   wire            i_rst_n,

        input   wire            i_uartRx,
        output  wire            o_uartTx,

        input   wire    [3:0]   i_gpioIn,
        output  wire    [3:0]   o_gpioOut,

        output  wire            o_halt
);

// core-side nets
wire            w_clkSys, w_clkUart, w_rst_n, w_uartRx;
wire    [3:0]   w_gpioIn;
wire            w_uartTx, w_halt;
wire    [3:0]   w_gpioOut;

`ifdef NO_PAD

assign w_clkSys  = i_clkSys;
assign w_clkUart = i_clkUart;
assign w_rst_n   = i_rst_n;
assign w_uartRx  = i_uartRx;
assign w_gpioIn  = i_gpioIn;
assign o_uartTx  = w_uartTx;
assign o_gpioOut = w_gpioOut;
assign o_halt    = w_halt;

`else

// ---------------- input PADs
PADDI u_pad_clkSys  (.PAD (i_clkSys),  .Y (w_clkSys));
PADDI u_pad_clkUart (.PAD (i_clkUart), .Y (w_clkUart));
PADDI u_pad_rst_n   (.PAD (i_rst_n),   .Y (w_rst_n));
PADDI u_pad_uartRx  (.PAD (i_uartRx),  .Y (w_uartRx));

genvar gi;
generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_pad_gpioIn
                PADDI u_pad (.PAD (i_gpioIn[gi]), .Y (w_gpioIn[gi]));
        end
        // ---------------- output PADs
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_pad_gpioOut
                PADDO u_pad (.A (w_gpioOut[gi]), .PAD (o_gpioOut[gi]));
        end
endgenerate

PADDO u_pad_uartTx  (.A (w_uartTx), .PAD (o_uartTx));
PADDO u_pad_halt    (.A (w_halt),   .PAD (o_halt));

`endif

// ---------------- MCU core (M4 block, unchanged)
mcu_top u_mcu (
        .i_clkSys       (w_clkSys),
        .i_clkUart      (w_clkUart),
        .i_rst_n        (w_rst_n),
        .i_uartRx       (w_uartRx),
        .o_uartTx       (w_uartTx),
        .i_gpioIn       (w_gpioIn),
        .o_gpioOut      (w_gpioOut),
        .o_halt         (w_halt)
);

endmodule
