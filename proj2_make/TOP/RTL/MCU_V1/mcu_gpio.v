`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_gpio  (APB3 slave, clk_sys) : 4 inputs + 4 outputs, fixed direction (spec 8)
//   0x00 DATA_IN    [3:0] R    i_gpioIn after a 2-FF synchronizer
//   0x04 DATA_OUT   [3:0] RW   o_gpioOut, reset 0
//   0x08 IRQ_EN     [3:0] RW   per-bit rising-edge interrupt enable
//   0x0C IRQ_STATUS [3:0] R/W1C set on a rising edge of DATA_IN ;
//                              a set and a W1C in the same cycle -> stays 1
//   o_irq = |(IRQ_STATUS & IRQ_EN)
//   0 wait states. Offsets are range-checked in mcu_dbus.
// -----------------------------------------------------------------------------
module mcu_gpio (
        input   wire            i_clk,
        input   wire            i_rst_n,

        input   wire            i_psel,
        input   wire            i_penable,
        input   wire            i_pwrite,
        input   wire    [11:0]  i_paddr,
        input   wire    [31:0]  i_pwdata,
        output  reg     [31:0]  o_prdata,
        output  wire            o_pready,
        output  wire            o_pslverr,

        input   wire    [3:0]   i_gpioIn,
        output  wire    [3:0]   o_gpioOut,
        output  wire            o_irq
);

reg     [3:0]   r_sync1, r_sync2, r_prev;
reg     [3:0]   r_out;
reg     [3:0]   r_irqEn;
reg     [3:0]   r_irqStatus;

wire            w_wr   = i_psel & i_penable & i_pwrite;
wire    [3:0]   w_rise = r_sync2 & ~r_prev;
wire    [3:0]   w_clr  = (w_wr && i_paddr[3:2] == 2'd3) ? i_pwdata[3:0] : 4'b0000;

assign o_pready  = 1'b1;
assign o_pslverr = 1'b0;
assign o_gpioOut = r_out;
assign o_irq     = |(r_irqStatus & r_irqEn);

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_sync1     <= 4'd0;
                r_sync2     <= 4'd0;
                r_prev      <= 4'd0;
                r_out       <= 4'd0;
                r_irqEn     <= 4'd0;
                r_irqStatus <= 4'd0;
        end else begin
                r_sync1     <= i_gpioIn;
                r_sync2     <= r_sync1;
                r_prev      <= r_sync2;
                if (w_wr && i_paddr[3:2] == 2'd1) r_out   <= i_pwdata[3:0];
                if (w_wr && i_paddr[3:2] == 2'd2) r_irqEn <= i_pwdata[3:0];
                r_irqStatus <= (r_irqStatus & ~w_clr) | w_rise;         // set wins
        end
end

always @(*) begin
        case (i_paddr[3:2])
                2'd0    : o_prdata = {28'd0, r_sync2};
                2'd1    : o_prdata = {28'd0, r_out};
                2'd2    : o_prdata = {28'd0, r_irqEn};
                default : o_prdata = {28'd0, r_irqStatus};
        endcase
end

endmodule
