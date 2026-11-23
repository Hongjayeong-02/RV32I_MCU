`timescale 1ns/1ps
`include "rv32_defs.vh"
// -----------------------------------------------------------------------------
// rv32_csr  (MEM stage)
//   Machine-mode CSRs (spec 6). Read is combinational (old value, same cycle),
//   every update happens at the clock edge of the cycle the MEM instruction
//   commits / traps. Update priority : trap > mret > CSR instruction write.
//
//   mstatus  0x300  MIE[3] MPIE[7] RW, MPP[12:11] = 11 fixed
//   misa     0x301  0x4000_0100 (RV32I), writes ignored
//   mie      0x304  MTIE[7] MEIE[11]
//   mtvec    0x305  [31:2] (direct mode)
//   mscratch 0x340, mepc 0x341 ([1:0] = 0), mcause 0x342 ({31, 3:0}), mtval 0x343
//   mip      0x344  MTIP[7] MEIP[11] from the interrupt inputs, writes ignored
//   mcycle / mcycleh 0xB00 / 0xB80, minstret / minstreth 0xB02 / 0xB82
//   mvendorid .. mhartid 0xF11 - 0xF14 read 0
//   anything else, or a write to 0xFxx (read-only) -> o_illegal
// -----------------------------------------------------------------------------
module rv32_csr (
        input   wire            i_clk,
        input   wire            i_rst_n,

        // CSR instruction in MEM
        input   wire    [11:0]  i_addr,
        input   wire    [1:0]   i_cmd,          // `CSR_RW / RS / RC
        input   wire            i_we,           // decoder: write really happens
        input   wire    [31:0]  i_src,          // rs1 (forwarded) or zimm
        input   wire            i_csrCommit,    // CSR instruction commits this cycle
        output  reg     [31:0]  o_rdata,
        output  reg             o_illegal,

        // trap / mret / retire (from MEM)
        input   wire            i_trap,
        input   wire    [31:0]  i_trapCause,
        input   wire    [31:0]  i_trapTval,
        input   wire    [31:0]  i_trapPc,
        input   wire            i_mret,
        input   wire            i_retire,       // an instruction commits this cycle

        // interrupt sources (level)
        input   wire            i_irqExt,
        input   wire            i_irqTimer,

        output  wire    [31:0]  o_mtvec,
        output  wire    [31:0]  o_mepc,
        output  wire            o_intPending,   // mstatus.MIE & (mip & mie) != 0
        output  wire    [31:0]  o_intCause
);

reg             r_mie;                  // mstatus.MIE
reg             r_mpie;                 // mstatus.MPIE
reg             r_meie, r_mtie;         // mie
reg     [29:0]  r_mtvec;                // [31:2]
reg     [31:0]  r_mscratch;
reg     [29:0]  r_mepc;                 // [31:2]
reg             r_mcauseInt;
reg     [3:0]   r_mcauseCode;
reg     [31:0]  r_mtval;
reg     [63:0]  r_mcycle;
reg     [63:0]  r_minstret;

wire    [31:0]  w_mstatus = {19'd0, 2'b11, 3'd0, r_mpie, 3'd0, r_mie, 3'd0};
wire    [31:0]  w_mip     = {20'd0, i_irqExt, 3'd0, i_irqTimer, 7'd0};
wire    [31:0]  w_mieReg  = {20'd0, r_meie, 3'd0, r_mtie, 7'd0};

// ---------------- read / legality ----------------
reg             r_known;
always @(*) begin
        r_known = 1'b1;
        case (i_addr)
                12'h300 : o_rdata = w_mstatus;
                12'h301 : o_rdata = 32'h4000_0100;
                12'h304 : o_rdata = w_mieReg;
                12'h305 : o_rdata = {r_mtvec, 2'b00};
                12'h340 : o_rdata = r_mscratch;
                12'h341 : o_rdata = {r_mepc, 2'b00};
                12'h342 : o_rdata = {r_mcauseInt, 27'd0, r_mcauseCode};
                12'h343 : o_rdata = r_mtval;
                12'h344 : o_rdata = w_mip;
                12'hB00 : o_rdata = r_mcycle[31:0];
                12'hB80 : o_rdata = r_mcycle[63:32];
                12'hB02 : o_rdata = r_minstret[31:0];
                12'hB82 : o_rdata = r_minstret[63:32];
                12'hF11, 12'hF12, 12'hF13, 12'hF14 : o_rdata = 32'd0;
                default : begin
                        o_rdata = 32'd0;
                        r_known = 1'b0;
                end
        endcase
        o_illegal = ~r_known | (i_we & (i_addr[11:10] == 2'b11));
end

// ---------------- write value ----------------
reg     [31:0]  r_wval;
always @(*) begin
        case (i_cmd)
                `CSR_RW : r_wval = i_src;
                `CSR_RS : r_wval = o_rdata | i_src;
                `CSR_RC : r_wval = o_rdata & ~i_src;
                default : r_wval = o_rdata;
        endcase
end

wire            w_wr = i_csrCommit & i_we & ~o_illegal & ~i_trap;

// ---------------- interrupt ----------------
wire            w_meiOn = i_irqExt   & r_meie;
wire            w_mtiOn = i_irqTimer & r_mtie;
assign o_intPending = r_mie & (w_meiOn | w_mtiOn);
assign o_intCause   = w_meiOn ? 32'h8000_000B : 32'h8000_0007;
assign o_mtvec      = {r_mtvec, 2'b00};
assign o_mepc       = {r_mepc, 2'b00};

// ---------------- state ----------------
always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_mie        <= 1'b0;
                r_mpie       <= 1'b0;
                r_meie       <= 1'b0;
                r_mtie       <= 1'b0;
                r_mtvec      <= 30'd0;
                r_mscratch   <= 32'd0;
                r_mepc       <= 30'd0;
                r_mcauseInt  <= 1'b0;
                r_mcauseCode <= 4'd0;
                r_mtval      <= 32'd0;
        end else if (i_trap) begin
                r_mepc       <= i_trapPc[31:2];
                r_mcauseInt  <= i_trapCause[31];
                r_mcauseCode <= i_trapCause[3:0];
                r_mtval      <= i_trapTval;
                r_mpie       <= r_mie;
                r_mie        <= 1'b0;
        end else if (i_mret) begin
                r_mie        <= r_mpie;
                r_mpie       <= 1'b1;
        end else if (w_wr) begin
                case (i_addr)
                        12'h300 : begin r_mie <= r_wval[3]; r_mpie <= r_wval[7]; end
                        12'h304 : begin r_mtie <= r_wval[7]; r_meie <= r_wval[11]; end
                        12'h305 : r_mtvec    <= r_wval[31:2];
                        12'h340 : r_mscratch <= r_wval;
                        12'h341 : r_mepc     <= r_wval[31:2];
                        12'h342 : begin r_mcauseInt <= r_wval[31]; r_mcauseCode <= r_wval[3:0]; end
                        12'h343 : r_mtval    <= r_wval;
                        default : ;
                endcase
        end
end

// counters : a CSR write wins over the increment of that cycle
//   minstret written by an instruction does not count that instruction
always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_mcycle   <= 64'd0;
                r_minstret <= 64'd0;
        end else begin
                if      (w_wr && i_addr == 12'hB00) r_mcycle <= {r_mcycle[63:32], r_wval};
                else if (w_wr && i_addr == 12'hB80) r_mcycle <= {r_wval, r_mcycle[31:0]};
                else                                r_mcycle <= r_mcycle + 64'd1;

                if      (w_wr && i_addr == 12'hB02) r_minstret <= {r_minstret[63:32], r_wval};
                else if (w_wr && i_addr == 12'hB82) r_minstret <= {r_wval, r_minstret[31:0]};
                else if (i_retire)                  r_minstret <= r_minstret + 64'd1;
        end
end

endmodule
