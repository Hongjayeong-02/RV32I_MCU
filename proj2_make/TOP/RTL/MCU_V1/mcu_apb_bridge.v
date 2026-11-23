`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mcu_apb_bridge  (clk_sys)
//   Core data request -> APB3 master, 4 slaves (spec 7).
//
//   IDLE   : i_req -> capture addr / data / write, go SETUP
//   SETUP  : PSEL = 1, PENABLE = 0
//   ACCESS : PENABLE = 1 until the selected PREADY = 1 ;
//            that cycle o_done = 1 with PRDATA / PSLVERR, back to IDLE
//
//   The core holds i_req and its address while waiting and moves on in the
//   cycle o_done = 1, so one request = exactly one APB transfer. A transfer
//   that has started is never aborted (the core does not take an interrupt
//   while a data access is outstanding, spec 6).
//   Fastest transfer : request in cycle t, done in t+2 (2 wait states).
// -----------------------------------------------------------------------------
module mcu_apb_bridge (
        input   wire            i_clk,
        input   wire            i_rst_n,

        input   wire            i_req,
        input   wire            i_we,
        input   wire    [31:0]  i_addr,
        input   wire    [31:0]  i_wdata,
        output  wire            o_done,
        output  wire    [31:0]  o_rdata,
        output  wire            o_err,

        // APB3 master
        output  reg     [11:0]  o_paddr,
        output  reg             o_pwrite,
        output  reg     [31:0]  o_pwdata,
        output  reg             o_penable,
        output  wire    [3:0]   o_psel,         // one-hot : UART, GPIO, TIMER, TEST
        input   wire    [127:0] i_prdata,       // {TEST, TIMER, GPIO, UART}
        input   wire    [3:0]   i_pready,
        input   wire    [3:0]   i_pslverr
);

localparam S_IDLE   = 2'd0;
localparam S_SETUP  = 2'd1;
localparam S_ACCESS = 2'd2;

reg     [1:0]   r_state;
reg     [1:0]   r_dev;

wire            w_ready  = i_pready[r_dev];
wire            w_access = (r_state == S_ACCESS);

assign o_psel  = (r_state == S_IDLE) ? 4'b0000 : (4'b0001 << r_dev);
assign o_done  = w_access & w_ready;
assign o_rdata = i_prdata[32*r_dev +: 32];
assign o_err   = i_pslverr[r_dev];

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_state   <= S_IDLE;
                r_dev     <= 2'd0;
                o_paddr   <= 12'd0;
                o_pwrite  <= 1'b0;
                o_pwdata  <= 32'd0;
                o_penable <= 1'b0;
        end else begin
                case (r_state)
                        S_IDLE : begin
                                if (i_req) begin
                                        r_state  <= S_SETUP;
                                        r_dev    <= i_addr[13:12];
                                        o_paddr  <= i_addr[11:0];
                                        o_pwrite <= i_we;
                                        o_pwdata <= i_wdata;
                                end
                        end
                        S_SETUP : begin
                                r_state   <= S_ACCESS;
                                o_penable <= 1'b1;
                        end
                        S_ACCESS : begin
                                if (w_ready) begin
                                        r_state   <= S_IDLE;
                                        o_penable <= 1'b0;
                                end
                        end
                        default : begin
                                r_state   <= S_IDLE;
                                o_penable <= 1'b0;
                        end
                endcase
        end
end

endmodule
