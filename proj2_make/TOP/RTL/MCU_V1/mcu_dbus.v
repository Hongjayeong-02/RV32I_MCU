`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_dbus  (combinational)
//   Data-side address decoder between the core MEM stage and the memories /
//   APB bridge (spec 7). The FULL address is compared (no aliasing).
//
//   ROM   0x0000_0000 - 0x0000_0FFF  read (port B), 0 wait ; write -> error
//   RAM   0x1000_0000 - 0x1000_03FF  read / write,  0 wait
//   APB   0x4000_0000 + dev*0x1000 + off, off < device size :
//           dev 0 UART 0x20, dev 1 GPIO 0x10, dev 2 TIMER 0x14, dev 3 TEST 0x0C
//         word write only (sub-word write -> error, APB3 has no byte strobes)
//         sub-word read is allowed (word read, the LSU extracts the lane)
//         ready / error come from the APB bridge (PREADY / PSLVERR)
//   anything else -> error at once (the core turns it into access fault 5 / 7)
// -----------------------------------------------------------------------------
module mcu_dbus (
        // core data port
        input   wire            i_req,
        input   wire            i_we,
        input   wire    [31:0]  i_addr,
        input   wire    [3:0]   i_be,
        output  reg     [31:0]  o_rdata,
        output  reg             o_ready,
        output  reg             o_err,

        // ROM port B
        input   wire    [31:0]  i_romData,

        // RAM
        output  wire    [3:0]   o_ramBe,
        input   wire    [31:0]  i_ramData,

        // APB bridge
        output  wire            o_apbReq,
        input   wire            i_apbDone,
        input   wire    [31:0]  i_apbRdata,
        input   wire            i_apbErr
);

wire            w_rom   = (i_addr[31:12] == 20'h00000);
wire            w_ram   = (i_addr[31:10] == 22'h040000);
wire            w_apbRg = (i_addr[31:14] == 18'h10000);

reg     [11:0]  r_devSize;
always @(*) begin
        case (i_addr[13:12])
                2'd0    : r_devSize = 12'h020;          // UART  : 8 registers
                2'd1    : r_devSize = 12'h010;          // GPIO  : 4
                2'd2    : r_devSize = 12'h014;          // TIMER : 5
                default : r_devSize = 12'h00C;          // TEST  : 3
        endcase
end

wire            w_apb   = w_apbRg & (i_addr[11:0] < r_devSize) & ~(i_we & (i_be != 4'b1111));

assign o_ramBe  = (i_req & i_we & w_ram) ? i_be : 4'b0000;
assign o_apbReq = i_req & w_apb;

always @(*) begin
        o_rdata = 32'd0;
        o_ready = 1'b1;
        o_err   = 1'b0;
        if (w_rom) begin
                o_rdata = i_romData;
                o_err   = i_we;
        end else if (w_ram) begin
                o_rdata = i_ramData;
        end else if (w_apb) begin
                o_rdata = i_apbRdata;
                o_ready = i_apbDone;
                o_err   = i_apbErr;
        end else begin
                o_err   = 1'b1;
        end
end

endmodule
