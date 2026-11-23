`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_timer  (APB3 slave, clk_sys) : RISC-V style mtime / mtimecmp (spec 8)
//   0x00 / 0x04 MTIME_LO / HI      64-bit counter, +1 every clk_sys while enabled
//   0x08 / 0x0C MTIMECMP_LO / HI   reset = all ones (no interrupt after reset)
//   0x10 CTRL [0] count enable, reset 1
//   o_mtip = (MTIME >= MTIMECMP), registered (one cycle late, spec 8).
//   A write to MTIME wins over the increment of that cycle.
//   Firmware writes MTIMECMP as LO = FFFF_FFFF, HI = new, LO = new so that
//   no false interrupt appears between the two halves.
//   0 wait states. Offsets are range-checked in mcu_dbus.
// -----------------------------------------------------------------------------
module mcu_timer (
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

        output  reg             o_mtip
);

reg     [63:0]  r_mtime;
reg     [63:0]  r_mtimecmp;
reg             r_en;

wire            w_wr = i_psel & i_penable & i_pwrite;

assign o_pready  = 1'b1;
assign o_pslverr = 1'b0;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_mtime    <= 64'd0;
                r_mtimecmp <= {64{1'b1}};
                r_en       <= 1'b1;
                o_mtip     <= 1'b0;
        end else begin
                if      (w_wr && i_paddr[4:2] == 3'd0) r_mtime <= {r_mtime[63:32], i_pwdata};
                else if (w_wr && i_paddr[4:2] == 3'd1) r_mtime <= {i_pwdata, r_mtime[31:0]};
                else if (r_en)                         r_mtime <= r_mtime + 64'd1;

                if (w_wr && i_paddr[4:2] == 3'd2) r_mtimecmp[31:0]  <= i_pwdata;
                if (w_wr && i_paddr[4:2] == 3'd3) r_mtimecmp[63:32] <= i_pwdata;
                if (w_wr && i_paddr[4:2] == 3'd4) r_en              <= i_pwdata[0];

                o_mtip <= (r_mtime >= r_mtimecmp);
        end
end

always @(*) begin
        case (i_paddr[4:2])
                3'd0    : o_prdata = r_mtime[31:0];
                3'd1    : o_prdata = r_mtime[63:32];
                3'd2    : o_prdata = r_mtimecmp[31:0];
                3'd3    : o_prdata = r_mtimecmp[63:32];
                default : o_prdata = {31'd0, r_en};
        endcase
end

endmodule
