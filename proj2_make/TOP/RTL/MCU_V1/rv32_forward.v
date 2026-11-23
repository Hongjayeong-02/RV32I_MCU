`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_forward  (ID stage, combinational)  -- pre-decoded forwarding (M4)
//   The forwarding decision is made one cycle EARLY, in ID, and registered in
//   ID/EX, so the EX critical path (fwd mux -> ALU / branch -> PC) no longer
//   starts with the rd == rs compares (synthesis M4 : worst path began at
//   r_memwbRd).
//
//   When the ID instruction enters EX at t+1 :
//     EX/MEM(t+1) = the instruction in EX now  (ID/EX now)
//     MEM/WB(t+1) = the instruction in MEM now (EX/MEM now)
//   so
//     o_selEx = it will forward from EX/MEM : ID/EX now valid & regWrite & rd != 0
//               & rd == rs & value ready in EX (not a load / CSR)
//     o_selWb = it will forward from MEM/WB : EX/MEM now valid & regWrite & rd != 0
//               & rd == rs & not selEx (EX/MEM is newer and wins)
//   The selects are captured only when ID/EX loads from ID (normal advance).
//   The cases where the guess would be wrong are handled in rv32_core :
//     - ID/EX bubble (load-use, redirect, trap) : selects cleared
//     - EX held (MEM wait) : the operand is re-captured with the forwarded
//       value and selWb is cleared (MEM/WB becomes a bubble), selEx kept
//     - EX/MEM(now) traps or waits : then ID/EX does not load from ID at all
//   A load / CSR result is never forwarded from EX/MEM : the load-use stall
//   puts a bubble in between and the value comes from MEM/WB.
// -----------------------------------------------------------------------------
module rv32_forward (
        // ID instruction
        input   wire    [4:0]   i_rs1,
        input   wire    [4:0]   i_rs2,
        input   wire            i_useRs1,
        input   wire            i_useRs2,

        // instruction in EX now (ID/EX) -> EX/MEM next cycle
        input   wire            i_idexValid,
        input   wire            i_idexRegWrite,
        input   wire            i_idexFwdOk,    // not a load / CSR
        input   wire    [4:0]   i_idexRd,

        // instruction in MEM now (EX/MEM) -> MEM/WB next cycle
        input   wire            i_exmemValid,
        input   wire            i_exmemRegWrite,
        input   wire    [4:0]   i_exmemRd,

        output  wire            o_selEx1,
        output  wire            o_selWb1,
        output  wire            o_selEx2,
        output  wire            o_selWb2
);

wire            w_exSrc = i_idexValid  & i_idexRegWrite  & i_idexFwdOk & (i_idexRd  != 5'd0);
wire            w_wbSrc = i_exmemValid & i_exmemRegWrite &               (i_exmemRd != 5'd0);

assign o_selEx1 = i_useRs1 & w_exSrc & (i_idexRd  == i_rs1);
assign o_selWb1 = i_useRs1 & w_wbSrc & (i_exmemRd == i_rs1) & ~o_selEx1;
assign o_selEx2 = i_useRs2 & w_exSrc & (i_idexRd  == i_rs2);
assign o_selWb2 = i_useRs2 & w_wbSrc & (i_exmemRd == i_rs2) & ~o_selEx2;

endmodule
