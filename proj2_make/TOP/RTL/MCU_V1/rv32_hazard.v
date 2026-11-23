`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_hazard  (combinational)
//   All stall / flush decisions in one place (spec 5, 6).
//   priority : MEM redirect (trap / mret) > MEM wait > EX redirect > load-use
//
//   MEM redirect : PC <- mtvec / mepc ; IF/ID, ID/EX, EX/MEM become bubbles.
//                  (MEM/WB : trap -> bubble, mret -> commits ; decided in core)
//   MEM wait     : data access not ready. PC, IF/ID, ID/EX, EX/MEM hold ;
//                  MEM/WB takes a bubble (older instruction retires once).
//                  EX redirect is not taken while waiting.
//   EX redirect  : taken branch / jal / jalr. PC <- target ; IF/ID, ID/EX bubbles.
//   load-use     : EX is a load or a CSR read (value appears in MEM) and the ID
//                  instruction really reads its rd -> PC, IF/ID hold, ID/EX bubble.
//   (MEM wait and MEM redirect never happen together : a trapping instruction
//    issues no request, a bus error comes back with ready.)
// -----------------------------------------------------------------------------
module rv32_hazard (
        // ID instruction (IF/ID)
        input   wire            i_ifidValid,
        input   wire    [4:0]   i_idRs1,
        input   wire    [4:0]   i_idRs2,
        input   wire            i_idUseRs1,
        input   wire            i_idUseRs2,
        // EX instruction (ID/EX)
        input   wire            i_idexValid,
        input   wire            i_idexLateWb,   // load or CSR : result known only in MEM
        input   wire            i_idexRegWrite,
        input   wire    [4:0]   i_idexRd,
        input   wire            i_exTaken,      // taken branch / jal / jalr (no exception)
        // MEM
        input   wire            i_memWait,
        input   wire            i_memRedirect,  // trap or mret

        output  reg             o_pcEn,
        output  reg     [1:0]   o_pcSel,        // 0 +4, 1 EX target, 2 MEM target
        output  reg             o_ifidEn,
        output  reg             o_ifidFlush,
        output  reg             o_idexEn,
        output  reg             o_idexFlush,
        output  reg             o_exmemEn,
        output  reg             o_exmemFlush,
        output  wire            o_loadUse
);

assign o_loadUse = i_idexValid & i_idexLateWb & i_idexRegWrite & (i_idexRd != 5'd0) &
                   i_ifidValid &
                   ((i_idUseRs1 & (i_idRs1 == i_idexRd)) |
                    (i_idUseRs2 & (i_idRs2 == i_idexRd)));

always @(*) begin
        o_pcEn       = 1'b1;
        o_pcSel      = 2'd0;
        o_ifidEn     = 1'b1;
        o_ifidFlush  = 1'b0;
        o_idexEn     = 1'b1;
        o_idexFlush  = 1'b0;
        o_exmemEn    = 1'b1;
        o_exmemFlush = 1'b0;

        if (i_memRedirect) begin
                o_pcSel      = 2'd2;
                o_ifidFlush  = 1'b1;
                o_idexFlush  = 1'b1;
                o_exmemFlush = 1'b1;
        end else if (i_memWait) begin
                o_pcEn       = 1'b0;
                o_ifidEn     = 1'b0;
                o_idexEn     = 1'b0;
                o_exmemEn    = 1'b0;
        end else if (i_idexValid && i_exTaken) begin
                o_pcSel      = 2'd1;
                o_ifidFlush  = 1'b1;
                o_idexFlush  = 1'b1;
        end else if (o_loadUse) begin
                o_pcEn       = 1'b0;
                o_ifidEn     = 1'b0;
                o_idexFlush  = 1'b1;
        end
end

endmodule
