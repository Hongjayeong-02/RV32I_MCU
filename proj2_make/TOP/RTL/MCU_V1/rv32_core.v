`timescale 1ns/1ps
`include "rv32_defs.vh"
// -----------------------------------------------------------------------------
// rv32_core  : RV32I + Zicsr + MRET, 5-stage pipeline  IF ID EX MEM WB (spec 5, 6)
//
//   IF  : PC -> instruction port (combinational ROM port A) ; PC outside the
//         instruction memory -> exception 1 (instruction access fault)
//   ID  : rv32_decoder, rv32_imm_gen, rv32_regfile ; illegal 2, ebreak 3, ecall 11
//   EX  : rv32_forward, rv32_alu, rv32_branch ; branch / jump redirect,
//         misaligned target -> exception 0 (no redirect)
//   MEM : COMMIT POINT. rv32_lsu, data port, rv32_csr.
//         exceptions found earlier travel with the instruction (excValid /
//         excCause / excTval) and are taken here, oldest first (precise).
//         load / store misaligned 4 / 6, bus error 5 / 7, CSR illegal 2.
//         interrupt : taken on a valid MEM instruction that has not started a
//         data access ; that instruction is not executed, mepc = its pc.
//         trap  -> PC <- mtvec, younger stages flushed, no commit
//         mret  -> PC <- mepc, younger stages flushed, mret commits
//   WB  : regfile write, commit trace port. The WB instruction is older than
//         any trap in MEM and always completes.
//
//   Hazards (rv32_hazard) : load / CSR-use 1 bubble, taken branch 2 bubbles,
//   trap / mret 3 bubbles, MEM wait holds PC..EX/MEM and bubbles MEM/WB.
//   Forwarding selects are decided in ID and registered (rv32_forward, M4 timing).
//   While EX is held, ID/EX re-captures its forwarded operands every cycle.
// -----------------------------------------------------------------------------
module rv32_core #(
        parameter IMEM_AW = 12                  // instruction memory 2**IMEM_AW bytes @ 0
)(
        input   wire            i_clk,
        input   wire            i_rst_n,

        // instruction port (IF)
        output  wire    [31:0]  o_imemAddr,
        input   wire    [31:0]  i_imemData,

        // data port (MEM)
        output  wire            o_dmemReq,
        output  wire            o_dmemWe,
        output  wire    [31:0]  o_dmemAddr,
        output  wire    [3:0]   o_dmemBe,
        output  wire    [31:0]  o_dmemWdata,
        input   wire    [31:0]  i_dmemRdata,
        input   wire            i_dmemReady,
        input   wire            i_dmemErr,      // with ready : unmapped / ROM write / PSLVERR

        // interrupts (level)
        input   wire            i_irqExt,
        input   wire            i_irqTimer,

        // commit trace (WB) : one pulse per retired instruction
        output  wire            o_cmtValid,
        output  wire    [31:0]  o_cmtPc,
        output  wire    [31:0]  o_cmtInst,
        output  wire            o_cmtRdWe,
        output  wire    [4:0]   o_cmtRd,
        output  wire    [31:0]  o_cmtRdVal,
        output  wire            o_cmtStWe,
        output  wire    [1:0]   o_cmtStSize,
        output  wire    [31:0]  o_cmtStAddr,
        output  wire    [31:0]  o_cmtStData,

        // trap event (MEM) : for the testbench / debug
        output  wire            o_trapValid,
        output  wire    [31:0]  o_trapCause,
        output  wire    [31:0]  o_trapPc
);

// =============================================================================
// hazard control
// =============================================================================
wire            w_pcEn;
wire    [1:0]   w_pcSel;
wire            w_ifidEn, w_ifidFlush;
wire            w_idexEn, w_idexFlush;
wire            w_exmemEn, w_exmemFlush;
wire            w_loadUse;
wire            w_memWait;
wire            w_memRedirect;
wire    [31:0]  w_memTarget;
wire            w_exTaken;
wire    [31:0]  w_exTarget;

// =============================================================================
// IF
// =============================================================================
reg     [31:0]  r_pc;

// PC[1:0] is always 0 (IALIGN = 32) : a misaligned jump traps instead of
// redirecting, mtvec / mepc keep [1:0] = 0. Written explicitly so that the
// constant is visible to LEC (Genus removed PC[1] as a sequential constant, M4).
always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)                   r_pc <= 32'd0;
        else if (w_pcSel == 2'd2)       r_pc <= {w_memTarget[31:2], 2'b00};
        else if (w_pcSel == 2'd1)       r_pc <= {w_exTarget[31:2], 2'b00};
        else if (w_pcEn)                r_pc <= {r_pc[31:2] + 30'd1, 2'b00};
end

assign o_imemAddr = r_pc;

wire            w_ifFault = (r_pc[31:IMEM_AW] != {(32-IMEM_AW){1'b0}});

// IF/ID
reg             r_ifidValid;
reg     [31:0]  r_ifidPc;
reg     [31:0]  r_ifidInst;
reg             r_ifidExc;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_ifidValid <= 1'b0;
                r_ifidPc    <= 32'd0;
                r_ifidInst  <= 32'h0000_0013;
                r_ifidExc   <= 1'b0;
        end else if (w_ifidFlush) begin
                r_ifidValid <= 1'b0;
                r_ifidInst  <= 32'h0000_0013;
                r_ifidExc   <= 1'b0;
        end else if (w_ifidEn) begin
                r_ifidValid <= 1'b1;
                r_ifidPc    <= {r_pc[31:2], 2'b00};
                r_ifidInst  <= w_ifFault ? 32'h0000_0013 : i_imemData;
                r_ifidExc   <= w_ifFault;
        end
end

// =============================================================================
// ID
// =============================================================================
wire    [3:0]   w_idAluOp;
wire    [1:0]   w_idASrc;
wire            w_idBSrc;
wire    [2:0]   w_idImmType;
wire            w_idUseRs1, w_idUseRs2;
wire            w_idRegWrite;
wire    [1:0]   w_idWbSel;
wire            w_idMemRead, w_idMemWrite;
wire    [1:0]   w_idMemSize;
wire            w_idMemUnsigned;
wire            w_idBranch, w_idJal, w_idJalr;
wire            w_idCsr, w_idCsrRe, w_idCsrWe;
wire    [1:0]   w_idCsrCmd;
wire            w_idEcall, w_idEbreak, w_idMret, w_idIllegal;
wire    [4:0]   w_idRd, w_idRs1, w_idRs2;
wire    [2:0]   w_idFunct3;
wire    [11:0]  w_idCsrAddr;
wire    [31:0]  w_idImm;
wire    [31:0]  w_idRs1Val, w_idRs2Val;

rv32_decoder u_decoder (
        .i_inst         (r_ifidInst),
        .o_aluOp        (w_idAluOp),
        .o_aSrc         (w_idASrc),
        .o_bSrc         (w_idBSrc),
        .o_immType      (w_idImmType),
        .o_useRs1       (w_idUseRs1),
        .o_useRs2       (w_idUseRs2),
        .o_regWrite     (w_idRegWrite),
        .o_wbSel        (w_idWbSel),
        .o_memRead      (w_idMemRead),
        .o_memWrite     (w_idMemWrite),
        .o_memSize      (w_idMemSize),
        .o_memUnsigned  (w_idMemUnsigned),
        .o_branch       (w_idBranch),
        .o_jal          (w_idJal),
        .o_jalr         (w_idJalr),
        .o_csr          (w_idCsr),
        .o_csrCmd       (w_idCsrCmd),
        .o_csrRe        (w_idCsrRe),
        .o_csrWe        (w_idCsrWe),
        .o_ecall        (w_idEcall),
        .o_ebreak       (w_idEbreak),
        .o_mret         (w_idMret),
        .o_illegal      (w_idIllegal),
        .o_rd           (w_idRd),
        .o_rs1          (w_idRs1),
        .o_rs2          (w_idRs2),
        .o_funct3       (w_idFunct3),
        .o_csrAddr      (w_idCsrAddr)
);

rv32_imm_gen u_imm_gen (
        .i_inst         (r_ifidInst),
        .i_immType      (w_idImmType),
        .o_imm          (w_idImm)
);

wire            w_wbWe;
wire    [4:0]   w_wbRd;
wire    [31:0]  w_wbData;

rv32_regfile u_regfile (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_we           (w_wbWe),
        .i_rd           (w_wbRd),
        .i_wdata        (w_wbData),
        .i_rs1          (w_idRs1),
        .i_rs2          (w_idRs2),
        .o_rs1Val       (w_idRs1Val),
        .o_rs2Val       (w_idRs2Val)
);

// ID exception (an IF fault is older and wins)
reg             r_idExc;
reg     [3:0]   r_idExcCause;
reg     [31:0]  r_idExcTval;
always @(*) begin
        r_idExc      = 1'b1;
        r_idExcCause = 4'd2;
        r_idExcTval  = r_ifidInst;
        if (r_ifidExc) begin
                r_idExcCause = 4'd1;  r_idExcTval = r_ifidPc;
        end else if (w_idIllegal) begin
                r_idExcCause = 4'd2;  r_idExcTval = r_ifidInst;
        end else if (w_idEbreak) begin
                r_idExcCause = 4'd3;  r_idExcTval = r_ifidPc;
        end else if (w_idEcall) begin
                r_idExcCause = 4'd11; r_idExcTval = 32'd0;
        end else begin
                r_idExc      = 1'b0;
        end
end

// an instruction with an exception has no side effect before MEM
wire            w_idOk = r_ifidValid & ~r_idExc;

// ID/EX
reg             r_idexValid;
reg     [31:0]  r_idexPc;
reg     [31:0]  r_idexInst;
reg     [4:0]   r_idexRd, r_idexRs1, r_idexRs2;
reg             r_idexUseRs1, r_idexUseRs2;
reg     [31:0]  r_idexRs1Val, r_idexRs2Val;
reg     [31:0]  r_idexImm;
reg     [3:0]   r_idexAluOp;
reg     [1:0]   r_idexASrc;
reg             r_idexBSrc;
reg             r_idexRegWrite;
reg     [1:0]   r_idexWbSel;
reg             r_idexMemRead, r_idexMemWrite;
reg     [1:0]   r_idexMemSize;
reg             r_idexMemUnsigned;
reg             r_idexBranch, r_idexJal, r_idexJalr;
reg     [2:0]   r_idexFunct3;
reg             r_idexCsr, r_idexCsrWe, r_idexMret;
reg     [1:0]   r_idexCsrCmd;
reg     [11:0]  r_idexCsrAddr;
reg             r_idexExc;
reg     [3:0]   r_idexExcCause;
reg     [31:0]  r_idexExcTval;
reg             r_idexSelEx1, r_idexSelWb1, r_idexSelEx2, r_idexSelWb2;   // pre-decoded forwarding

wire    [31:0]  w_exRs1Fwd, w_exRs2Fwd;
wire            w_idSelEx1, w_idSelWb1, w_idSelEx2, w_idSelWb2;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_idexValid       <= 1'b0;
                r_idexPc          <= 32'd0;
                r_idexInst        <= 32'h0000_0013;
                r_idexRd          <= 5'd0;
                r_idexRs1         <= 5'd0;
                r_idexRs2         <= 5'd0;
                r_idexUseRs1      <= 1'b0;
                r_idexUseRs2      <= 1'b0;
                r_idexRs1Val      <= 32'd0;
                r_idexRs2Val      <= 32'd0;
                r_idexImm         <= 32'd0;
                r_idexAluOp       <= `ALU_ADD;
                r_idexASrc        <= `ASRC_RS1;
                r_idexBSrc        <= `BSRC_IMM;
                r_idexRegWrite    <= 1'b0;
                r_idexWbSel       <= `WB_ALU;
                r_idexMemRead     <= 1'b0;
                r_idexMemWrite    <= 1'b0;
                r_idexMemSize     <= 2'd0;
                r_idexMemUnsigned <= 1'b0;
                r_idexBranch      <= 1'b0;
                r_idexJal         <= 1'b0;
                r_idexJalr        <= 1'b0;
                r_idexFunct3      <= 3'd0;
                r_idexCsr         <= 1'b0;
                r_idexCsrWe       <= 1'b0;
                r_idexCsrCmd      <= 2'd0;
                r_idexCsrAddr     <= 12'd0;
                r_idexMret        <= 1'b0;
                r_idexExc         <= 1'b0;
                r_idexExcCause    <= 4'd0;
                r_idexExcTval     <= 32'd0;
                r_idexSelEx1      <= 1'b0;
                r_idexSelWb1      <= 1'b0;
                r_idexSelEx2      <= 1'b0;
                r_idexSelWb2      <= 1'b0;
        end else if (!w_idexEn) begin
                // held (MEM wait) : keep the instruction, re-capture the forwarded
                // operands ; MEM/WB turns into a bubble, so stop selecting it
                // (EX/MEM is the waiting instruction itself and stays : keep selEx)
                r_idexRs1Val      <= w_exRs1Fwd;
                r_idexRs2Val      <= w_exRs2Fwd;
                r_idexSelWb1      <= 1'b0;
                r_idexSelWb2      <= 1'b0;
        end else if (w_idexFlush) begin
                r_idexValid       <= 1'b0;
                r_idexInst        <= 32'h0000_0013;
                r_idexRd          <= 5'd0;
                r_idexUseRs1      <= 1'b0;
                r_idexUseRs2      <= 1'b0;
                r_idexRegWrite    <= 1'b0;
                r_idexMemRead     <= 1'b0;
                r_idexMemWrite    <= 1'b0;
                r_idexBranch      <= 1'b0;
                r_idexJal         <= 1'b0;
                r_idexJalr        <= 1'b0;
                r_idexCsr         <= 1'b0;
                r_idexCsrWe       <= 1'b0;
                r_idexMret        <= 1'b0;
                r_idexExc         <= 1'b0;
                r_idexSelEx1      <= 1'b0;
                r_idexSelWb1      <= 1'b0;
                r_idexSelEx2      <= 1'b0;
                r_idexSelWb2      <= 1'b0;
        end else begin
                r_idexValid       <= r_ifidValid;
                r_idexPc          <= {r_ifidPc[31:2], 2'b00};
                r_idexInst        <= r_ifidInst;
                r_idexRd          <= w_idRd;
                r_idexRs1         <= w_idRs1;
                r_idexRs2         <= w_idRs2;
                r_idexUseRs1      <= w_idUseRs1;
                r_idexUseRs2      <= w_idUseRs2;
                r_idexRs1Val      <= w_idRs1Val;
                r_idexRs2Val      <= w_idRs2Val;
                r_idexImm         <= w_idImm;
                r_idexAluOp       <= w_idAluOp;
                r_idexASrc        <= w_idASrc;
                r_idexBSrc        <= w_idBSrc;
                r_idexRegWrite    <= w_idRegWrite & w_idOk;
                r_idexWbSel       <= w_idWbSel;
                r_idexMemRead     <= w_idMemRead  & w_idOk;
                r_idexMemWrite    <= w_idMemWrite & w_idOk;
                r_idexMemSize     <= w_idMemSize;
                r_idexMemUnsigned <= w_idMemUnsigned;
                r_idexBranch      <= w_idBranch & w_idOk;
                r_idexJal         <= w_idJal    & w_idOk;
                r_idexJalr        <= w_idJalr   & w_idOk;
                r_idexFunct3      <= w_idFunct3;
                r_idexCsr         <= w_idCsr    & w_idOk;
                r_idexCsrWe       <= w_idCsrWe;
                r_idexCsrCmd      <= w_idCsrCmd;
                r_idexCsrAddr     <= w_idCsrAddr;
                r_idexMret        <= w_idMret   & w_idOk;
                r_idexExc         <= r_idExc & r_ifidValid;
                r_idexExcCause    <= r_idExcCause;
                r_idexExcTval     <= r_idExcTval;
                r_idexSelEx1      <= w_idSelEx1;
                r_idexSelWb1      <= w_idSelWb1;
                r_idexSelEx2      <= w_idSelEx2;
                r_idexSelWb2      <= w_idSelWb2;
        end
end

// =============================================================================
// EX
// =============================================================================
reg             r_exmemValid;
reg     [31:0]  r_exmemPc;
reg     [31:0]  r_exmemInst;
reg     [4:0]   r_exmemRd;
reg             r_exmemRegWrite;
reg             r_exmemMemRead, r_exmemMemWrite;
reg     [1:0]   r_exmemMemSize;
reg             r_exmemMemUnsigned;
reg     [31:0]  r_exmemAddr;
reg     [31:0]  r_exmemStoreData;
reg     [31:0]  r_exmemResult;
reg             r_exmemCsr, r_exmemCsrWe, r_exmemMret;
reg     [1:0]   r_exmemCsrCmd;
reg     [11:0]  r_exmemCsrAddr;
reg             r_exmemExc;
reg     [3:0]   r_exmemExcCause;
reg     [31:0]  r_exmemExcTval;

reg             r_memwbValid;
reg     [31:0]  r_memwbPc;
reg     [31:0]  r_memwbInst;
reg     [4:0]   r_memwbRd;
reg             r_memwbRegWrite;
reg     [31:0]  r_memwbData;
reg             r_memwbStWe;
reg     [1:0]   r_memwbStSize;
reg     [31:0]  r_memwbStAddr;
reg     [31:0]  r_memwbStData;

// forwarding : decided in ID (rv32_forward), applied here with registered selects
rv32_forward u_forward (
        .i_rs1          (w_idRs1),
        .i_rs2          (w_idRs2),
        .i_useRs1       (w_idUseRs1),
        .i_useRs2       (w_idUseRs2),
        .i_idexValid    (r_idexValid),
        .i_idexRegWrite (r_idexRegWrite),
        .i_idexFwdOk    (~r_idexMemRead & ~r_idexCsr),
        .i_idexRd       (r_idexRd),
        .i_exmemValid   (r_exmemValid),
        .i_exmemRegWrite(r_exmemRegWrite),
        .i_exmemRd      (r_exmemRd),
        .o_selEx1       (w_idSelEx1),
        .o_selWb1       (w_idSelWb1),
        .o_selEx2       (w_idSelEx2),
        .o_selWb2       (w_idSelWb2)
);

assign w_exRs1Fwd = r_idexSelEx1 ? r_exmemResult : r_idexSelWb1 ? r_memwbData : r_idexRs1Val;
assign w_exRs2Fwd = r_idexSelEx2 ? r_exmemResult : r_idexSelWb2 ? r_memwbData : r_idexRs2Val;

reg     [31:0]  r_exOpA;
wire    [31:0]  w_exOpB = (r_idexBSrc == `BSRC_RS2) ? w_exRs2Fwd : r_idexImm;
wire    [31:0]  w_exAluY;
wire            w_exBrTaken;
wire    [31:0]  w_exPc4 = r_idexPc + 32'd4;

always @(*) begin
        case (r_idexASrc)
                `ASRC_PC   : r_exOpA = r_idexPc;
                `ASRC_ZERO : r_exOpA = 32'd0;
                default    : r_exOpA = w_exRs1Fwd;
        endcase
end

rv32_alu u_alu (
        .i_aluOp        (r_idexAluOp),
        .i_opA          (r_exOpA),
        .i_opB          (w_exOpB),
        .o_result       (w_exAluY)
);

rv32_branch u_branch (
        .i_funct3       (r_idexFunct3),
        .i_rs1Val       (w_exRs1Fwd),
        .i_rs2Val       (w_exRs2Fwd),
        .o_taken        (w_exBrTaken)
);

// target : branch / jal = pc + imm ; jalr = (rs1 + imm) & ~1
wire            w_exJump      = (r_idexBranch & w_exBrTaken) | r_idexJal | r_idexJalr;
assign          w_exTarget    = r_idexJalr ? {w_exAluY[31:1], 1'b0} : w_exAluY;
wire            w_exMisalign  = w_exJump & w_exTarget[1];           // IALIGN = 32
assign          w_exTaken     = w_exJump & ~w_exMisalign;

wire    [31:0]  w_exResult    = (r_idexWbSel == `WB_PC4) ? w_exPc4 : w_exAluY;
// CSR write source : zimm (funct3[2]) or forwarded rs1
wire    [31:0]  w_exCsrSrc    = r_idexFunct3[2] ? r_idexImm : w_exRs1Fwd;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_exmemValid       <= 1'b0;
                r_exmemPc          <= 32'd0;
                r_exmemInst        <= 32'h0000_0013;
                r_exmemRd          <= 5'd0;
                r_exmemRegWrite    <= 1'b0;
                r_exmemMemRead     <= 1'b0;
                r_exmemMemWrite    <= 1'b0;
                r_exmemMemSize     <= 2'd0;
                r_exmemMemUnsigned <= 1'b0;
                r_exmemAddr        <= 32'd0;
                r_exmemStoreData   <= 32'd0;
                r_exmemResult      <= 32'd0;
                r_exmemCsr         <= 1'b0;
                r_exmemCsrWe       <= 1'b0;
                r_exmemCsrCmd      <= 2'd0;
                r_exmemCsrAddr     <= 12'd0;
                r_exmemMret        <= 1'b0;
                r_exmemExc         <= 1'b0;
                r_exmemExcCause    <= 4'd0;
                r_exmemExcTval     <= 32'd0;
        end else if (w_exmemFlush) begin
                r_exmemValid       <= 1'b0;
                r_exmemRegWrite    <= 1'b0;
                r_exmemMemRead     <= 1'b0;
                r_exmemMemWrite    <= 1'b0;
                r_exmemCsr         <= 1'b0;
                r_exmemMret        <= 1'b0;
                r_exmemExc         <= 1'b0;
        end else if (w_exmemEn) begin
                r_exmemValid       <= r_idexValid;
                r_exmemPc          <= r_idexPc;
                r_exmemInst        <= r_idexInst;
                r_exmemRd          <= r_idexRd;
                r_exmemRegWrite    <= r_idexRegWrite;
                r_exmemMemRead     <= r_idexMemRead;
                r_exmemMemWrite    <= r_idexMemWrite;
                r_exmemMemSize     <= r_idexMemSize;
                r_exmemMemUnsigned <= r_idexMemUnsigned;
                r_exmemAddr        <= w_exAluY;
                r_exmemStoreData   <= r_idexCsr ? w_exCsrSrc : w_exRs2Fwd;
                r_exmemResult      <= w_exResult;
                r_exmemCsr         <= r_idexCsr;
                r_exmemCsrWe       <= r_idexCsrWe;
                r_exmemCsrCmd      <= r_idexCsrCmd;
                r_exmemCsrAddr     <= r_idexCsrAddr;
                r_exmemMret        <= r_idexMret;
                r_exmemExc         <= r_idexExc | (r_idexValid & w_exMisalign);
                r_exmemExcCause    <= r_idexExc ? r_idexExcCause : 4'd0;
                r_exmemExcTval     <= r_idexExc ? r_idexExcTval  : w_exTarget;
        end
end

// =============================================================================
// MEM  (commit point)
// =============================================================================
wire    [3:0]   w_memBe;
wire    [31:0]  w_memWdata;
wire    [31:0]  w_memLoadData;
wire            w_memMisaligned;

rv32_lsu u_lsu (
        .i_addrLo       (r_exmemAddr[1:0]),
        .i_size         (r_exmemMemSize),
        .i_unsigned     (r_exmemMemUnsigned),
        .i_store        (r_exmemMemWrite),
        .i_storeData    (r_exmemStoreData),
        .i_rdata        (i_dmemRdata),
        .o_be           (w_memBe),
        .o_wdata        (w_memWdata),
        .o_loadData     (w_memLoadData),
        .o_misaligned   (w_memMisaligned)
);

wire    [31:0]  w_csrRdata;
wire            w_csrIllegal;
wire    [31:0]  w_mtvec, w_mepc;
wire            w_intPending;
wire    [31:0]  w_intCause;

wire            w_memAccess = r_exmemMemRead | r_exmemMemWrite;

// an access that has been issued but not finished (wait state) cannot be interrupted
reg             r_memStarted;

wire            w_intTake = w_intPending & r_exmemValid & ~r_memStarted;

// exceptions found in MEM before any access
wire            w_memEarlyExc = r_exmemExc | (r_exmemCsr & w_csrIllegal) |
                                (w_memAccess & w_memMisaligned);

assign o_dmemReq   = r_exmemValid & w_memAccess & ~w_memEarlyExc & ~w_intTake;
assign o_dmemWe    = r_exmemMemWrite;
assign o_dmemAddr  = r_exmemAddr;
assign o_dmemBe    = w_memBe;
assign o_dmemWdata = w_memWdata;

assign w_memWait   = o_dmemReq & ~i_dmemReady;
wire            w_busErr = o_dmemReq & i_dmemReady & i_dmemErr;

// trap selection (interrupt first : the MEM instruction is not executed)
reg             r_trap;
reg     [31:0]  r_trapCause;
reg     [31:0]  r_trapTval;
always @(*) begin
        r_trap      = r_exmemValid;
        r_trapCause = 32'd0;
        r_trapTval  = 32'd0;
        if (w_intTake) begin
                r_trapCause = w_intCause;
        end else if (r_exmemExc) begin
                r_trapCause = {28'd0, r_exmemExcCause};
                r_trapTval  = r_exmemExcTval;
        end else if (r_exmemCsr && w_csrIllegal) begin
                r_trapCause = 32'd2;
                r_trapTval  = r_exmemInst;
        end else if (w_memAccess && w_memMisaligned) begin
                r_trapCause = r_exmemMemWrite ? 32'd6 : 32'd4;
                r_trapTval  = r_exmemAddr;
        end else if (w_busErr) begin
                r_trapCause = r_exmemMemWrite ? 32'd7 : 32'd5;
                r_trapTval  = r_exmemAddr;
        end else begin
                r_trap      = 1'b0;
        end
end

wire            w_commit = r_exmemValid & ~r_trap & ~w_memWait;
wire            w_mretGo = w_commit & r_exmemMret;

assign w_memRedirect = r_trap | w_mretGo;
assign w_memTarget   = r_trap ? w_mtvec : w_mepc;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)   r_memStarted <= 1'b0;
        else            r_memStarted <= w_memWait;
end

rv32_csr u_csr (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_addr         (r_exmemCsrAddr),
        .i_cmd          (r_exmemCsrCmd),
        .i_we           (r_exmemCsrWe),
        .i_src          (r_exmemStoreData),
        .i_csrCommit    (w_commit & r_exmemCsr),
        .o_rdata        (w_csrRdata),
        .o_illegal      (w_csrIllegal),
        .i_trap         (r_trap),
        .i_trapCause    (r_trapCause),
        .i_trapTval     (r_trapTval),
        .i_trapPc       (r_exmemPc),
        .i_mret         (w_mretGo),
        .i_retire       (w_commit),
        .i_irqExt       (i_irqExt),
        .i_irqTimer     (i_irqTimer),
        .o_mtvec        (w_mtvec),
        .o_mepc         (w_mepc),
        .o_intPending   (w_intPending),
        .o_intCause     (w_intCause)
);

assign o_trapValid = r_trap;
assign o_trapCause = r_trapCause;
assign o_trapPc    = r_exmemPc;

always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
                r_memwbValid    <= 1'b0;
                r_memwbPc       <= 32'd0;
                r_memwbInst     <= 32'h0000_0013;
                r_memwbRd       <= 5'd0;
                r_memwbRegWrite <= 1'b0;
                r_memwbData     <= 32'd0;
                r_memwbStWe     <= 1'b0;
                r_memwbStSize   <= 2'd0;
                r_memwbStAddr   <= 32'd0;
                r_memwbStData   <= 32'd0;
        end else if (!w_commit) begin
                // bubble : MEM wait, trap, or empty MEM
                r_memwbValid    <= 1'b0;
                r_memwbRegWrite <= 1'b0;
                r_memwbStWe     <= 1'b0;
        end else begin
                r_memwbValid    <= 1'b1;
                r_memwbPc       <= r_exmemPc;
                r_memwbInst     <= r_exmemInst;
                r_memwbRd       <= r_exmemRd;
                r_memwbRegWrite <= r_exmemRegWrite;
                r_memwbData     <= r_exmemMemRead ? w_memLoadData :
                                   r_exmemCsr     ? w_csrRdata    : r_exmemResult;
                r_memwbStWe     <= r_exmemMemWrite;
                r_memwbStSize   <= r_exmemMemSize;
                r_memwbStAddr   <= r_exmemAddr;
                r_memwbStData   <= r_exmemStoreData;
        end
end

// =============================================================================
// WB
// =============================================================================
assign w_wbWe   = r_memwbValid & r_memwbRegWrite;
assign w_wbRd   = r_memwbRd;
assign w_wbData = r_memwbData;

assign o_cmtValid  = r_memwbValid;
assign o_cmtPc     = r_memwbPc;
assign o_cmtInst   = r_memwbInst;
assign o_cmtRdWe   = w_wbWe & (r_memwbRd != 5'd0);
assign o_cmtRd     = r_memwbRd;
assign o_cmtRdVal  = r_memwbData;
assign o_cmtStWe   = r_memwbStWe;
assign o_cmtStSize = r_memwbStSize;
assign o_cmtStAddr = r_memwbStAddr;
assign o_cmtStData = (r_memwbStSize == 2'd0) ? {24'd0, r_memwbStData[7:0]}  :
                     (r_memwbStSize == 2'd1) ? {16'd0, r_memwbStData[15:0]} :
                                               r_memwbStData;

// =============================================================================
// hazard unit
// =============================================================================
rv32_hazard u_hazard (
        .i_ifidValid    (r_ifidValid),
        .i_idRs1        (w_idRs1),
        .i_idRs2        (w_idRs2),
        .i_idUseRs1     (w_idUseRs1),
        .i_idUseRs2     (w_idUseRs2),
        .i_idexValid    (r_idexValid),
        .i_idexLateWb   (r_idexMemRead | r_idexCsr),
        .i_idexRegWrite (r_idexRegWrite),
        .i_idexRd       (r_idexRd),
        .i_exTaken      (w_exTaken),
        .i_memWait      (w_memWait),
        .i_memRedirect  (w_memRedirect),
        .o_pcEn         (w_pcEn),
        .o_pcSel        (w_pcSel),
        .o_ifidEn       (w_ifidEn),
        .o_ifidFlush    (w_ifidFlush),
        .o_idexEn       (w_idexEn),
        .o_idexFlush    (w_idexFlush),
        .o_exmemEn      (w_exmemEn),
        .o_exmemFlush   (w_exmemFlush),
        .o_loadUse      (w_loadUse)
);

endmodule
