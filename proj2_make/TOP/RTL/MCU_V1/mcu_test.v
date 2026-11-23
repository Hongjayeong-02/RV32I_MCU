`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_test  (APB3 slave, clk_sys) : test result / halt device (spec 8)
//   0x00 TEST_STATUS  W : [0] PASS(1) / FAIL(0), any write sets o_halt
//                     R : {30'd0, halt, pass}
//   0x04 TEST_RESULT  RW : failing test number or a checksum
//   0x08 TEST_IRQ     RW [1:0] : software interrupt request, bit0 -> MEIP,
//                     bit1 -> MTIP (ORed with UART/GPIO and the timer, spec 6 Rev 1.2)
//   0 wait states. Offsets are range-checked in mcu_dbus.
// -----------------------------------------------------------------------------
module mcu_test (
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

        output  reg             o_halt,
        output  reg             o_pass,
        output  reg     [1:0]   o_irq
);

reg     [31:0]  r_result;

wire            w_wr = i_psel & i_penable & i_pwrite;

assign o_pready  = 1'b1;
assign o_pslverr = 1'b0;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                o_halt   <= 1'b0;
                o_pass   <= 1'b0;
                o_irq    <= 2'b00;
                r_result <= 32'd0;
        end else begin
                if (w_wr && i_paddr[3:2] == 2'd0) begin
                        o_halt <= 1'b1;
                        o_pass <= i_pwdata[0];
                end
                if (w_wr && i_paddr[3:2] == 2'd1) r_result <= i_pwdata;
                if (w_wr && i_paddr[3:2] == 2'd2) o_irq    <= i_pwdata[1:0];
        end
end

always @(*) begin
        case (i_paddr[3:2])
                2'd0    : o_prdata = {30'd0, o_halt, o_pass};
                2'd1    : o_prdata = r_result;
                default : o_prdata = {30'd0, o_irq};
        endcase
end

endmodule
