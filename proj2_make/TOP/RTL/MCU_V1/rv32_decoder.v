`timescale 1ns/1ps
`include "rv32_defs.vh"
// -----------------------------------------------------------------------------
// rv32_decoder  (ID stage, combinational)
//   RV32I(40) + Zicsr(6) + MRET = 47 instructions
//   - every unsupported encoding -> o_illegal = 1, all side-effect
//     controls (reg/mem/csr write, branch/jump) forced to 0
//   - o_regWrite is already gated by rd != x0
//   - CSR address legality (unknown / read-only write) is checked
//     later in rv32_csr at MEM, not here
// -----------------------------------------------------------------------------
module rv32_decoder (
        input   wire    [31:0]  i_inst,

        // operand / ALU
        output  reg     [3:0]   o_aluOp,
        output  reg     [1:0]   o_aSrc,             // `ASRC_*
        output  reg             o_bSrc,             // `BSRC_*
        output  reg     [2:0]   o_immType,          // `IMM_*
        output  reg             o_useRs1,           // instruction really reads rs1 (hazard/forward)
        output  reg             o_useRs2,           // instruction really reads rs2

        // write-back
        output  reg             o_regWrite,
        output  reg     [1:0]   o_wbSel,            // `WB_*

        // memory
        output  reg             o_memRead,
        output  reg             o_memWrite,
        output  reg     [1:0]   o_memSize,          // 0=byte 1=half 2=word (funct3[1:0])
        output  reg             o_memUnsigned,      // funct3[2] for LBU/LHU

        // control flow
        output  reg             o_branch,           // conditional branch, cond = funct3
        output  reg             o_jal,
        output  reg             o_jalr,

        // CSR (executed in MEM)
        output  reg             o_csr,              // any CSR instruction
        output  reg     [1:0]   o_csrCmd,           // `CSR_RW / RS / RC
        output  reg             o_csrRe,            // read side effect allowed (CSRRW rd=x0 -> 0)
        output  reg             o_csrWe,            // write happens (RS/RC with x0 or zimm=0 -> 0)

        // system / exceptions
        output  reg             o_ecall,
        output  reg             o_ebreak,
        output  reg             o_mret,
        output  reg             o_illegal,

        // fields (convenience)
        output  wire    [4:0]   o_rd,
        output  wire    [4:0]   o_rs1,
        output  wire    [4:0]   o_rs2,
        output  wire    [2:0]   o_funct3,
        output  wire    [11:0]  o_csrAddr
);

wire    [6:0]   w_opcode  = i_inst[6:0];
wire    [2:0]   w_funct3  = i_inst[14:12];
wire    [6:0]   w_funct7  = i_inst[31:25];
wire            w_rdNz    = (i_inst[11:7]  != 5'd0);
wire            w_rs1Nz   = (i_inst[19:15] != 5'd0);

// R-type funct7 legality : 0000000 for all, 0100000 only for SUB / SRA
wire            w_f7Zero  = (w_funct7 == 7'b0000000);
wire            w_f7Alt   = (w_funct7 == 7'b0100000);

assign o_rd      = i_inst[11:7];
assign o_rs1     = i_inst[19:15];
assign o_rs2     = i_inst[24:20];
assign o_funct3  = w_funct3;
assign o_csrAddr = i_inst[31:20];

always @(*) begin
        // ---------- safe defaults (= NOP, legal) ----------
        o_aluOp       = `ALU_ADD;
        o_aSrc        = `ASRC_RS1;
        o_bSrc        = `BSRC_IMM;
        o_immType     = `IMM_I;
        o_useRs1      = 1'b0;
        o_useRs2      = 1'b0;
        o_regWrite    = 1'b0;
        o_wbSel       = `WB_ALU;
        o_memRead     = 1'b0;
        o_memWrite    = 1'b0;
        o_memSize     = w_funct3[1:0];
        o_memUnsigned = w_funct3[2];
        o_branch      = 1'b0;
        o_jal         = 1'b0;
        o_jalr        = 1'b0;
        o_csr         = 1'b0;
        o_csrCmd      = w_funct3[1:0];
        o_csrRe       = 1'b0;
        o_csrWe       = 1'b0;
        o_ecall       = 1'b0;
        o_ebreak      = 1'b0;
        o_mret        = 1'b0;
        o_illegal     = 1'b0;

        if (i_inst[1:0] != 2'b11) begin
                o_illegal     = 1'b1;                       // compressed / garbage
        end else begin
                case (w_opcode)
                        // ---------------- U-type ----------------
                        `OP_LUI : begin
                                o_aluOp       = `ALU_PASSB;
                                o_immType     = `IMM_U;
                                o_regWrite    = w_rdNz;
                        end
                        `OP_AUIPC : begin
                                o_aSrc        = `ASRC_PC;
                                o_immType     = `IMM_U;
                                o_regWrite    = w_rdNz;
                        end
                        // ---------------- jumps -----------------
                        `OP_JAL : begin
                                o_aSrc        = `ASRC_PC;             // ALU = pc + imm (target)
                                o_immType     = `IMM_J;
                                o_jal         = 1'b1;
                                o_wbSel       = `WB_PC4;
                                o_regWrite    = w_rdNz;
                        end
                        `OP_JALR : begin
                                if (w_funct3 == 3'b000) begin
                                        o_immType     = `IMM_I;           // ALU = rs1 + imm (target, bit0 cleared later)
                                        o_useRs1      = 1'b1;
                                        o_jalr        = 1'b1;
                                        o_wbSel       = `WB_PC4;
                                        o_regWrite    = w_rdNz;
                                end else begin
                                        o_illegal     = 1'b1;
                                end
                        end
                        // ---------------- branch ----------------
                        `OP_BRANCH : begin
                                if (w_funct3 == 3'b010 || w_funct3 == 3'b011) begin
                                        o_illegal     = 1'b1;
                                end else begin
                                        o_aSrc        = `ASRC_PC;          // ALU = pc + imm (target)
                                        o_immType     = `IMM_B;
                                        o_useRs1      = 1'b1;              // compare in rv32_branch
                                        o_useRs2      = 1'b1;
                                        o_branch      = 1'b1;
                                end
                        end
                        // ---------------- load ------------------
                        `OP_LOAD : begin
                                case (w_funct3)
                                        3'b000, 3'b001, 3'b010, 3'b100, 3'b101 : begin
                                                o_immType     = `IMM_I;
                                                o_useRs1      = 1'b1;
                                                o_memRead     = 1'b1;
                                                o_wbSel       = `WB_MEM;
                                                o_regWrite    = w_rdNz;
                                        end
                                        default : o_illegal = 1'b1;
                                endcase
                        end
                        // ---------------- store -----------------
                        `OP_STORE : begin
                                case (w_funct3)
                                        3'b000, 3'b001, 3'b010 : begin
                                                o_immType     = `IMM_S;
                                                o_useRs1      = 1'b1;
                                                o_useRs2      = 1'b1;         // store data
                                                o_memWrite    = 1'b1;
                                        end
                                        default : o_illegal = 1'b1;
                                endcase
                        end
                        // ---------------- ALU immediate ---------
                        `OP_IMM : begin
                                o_immType     = `IMM_I;
                                o_useRs1      = 1'b1;
                                o_regWrite    = w_rdNz;
                                case (w_funct3)
                                        3'b000 : o_aluOp = `ALU_ADD;
                                        3'b010 : o_aluOp = `ALU_SLT;
                                        3'b011 : o_aluOp = `ALU_SLTU;
                                        3'b100 : o_aluOp = `ALU_XOR;
                                        3'b110 : o_aluOp = `ALU_OR;
                                        3'b111 : o_aluOp = `ALU_AND;
                                        3'b001 : begin                  // SLLI : funct7 must be 0
                                                o_aluOp       = `ALU_SLL;
                                                if (!w_f7Zero) o_illegal = 1'b1;
                                        end
                                        3'b101 : begin                  // SRLI / SRAI
                                                if      (w_f7Zero) o_aluOp = `ALU_SRL;
                                                else if (w_f7Alt)  o_aluOp = `ALU_SRA;
                                                else                o_illegal = 1'b1;
                                        end
                                        default : o_illegal = 1'b1;
                                endcase
                        end
                        // ---------------- ALU register ----------
                        `OP_REG : begin
                                o_bSrc        = `BSRC_RS2;
                                o_useRs1      = 1'b1;
                                o_useRs2      = 1'b1;
                                o_regWrite    = w_rdNz;
                                if (w_f7Zero) begin
                                        case (w_funct3)
                                                3'b000  : o_aluOp = `ALU_ADD;
                                                3'b001  : o_aluOp = `ALU_SLL;
                                                3'b010  : o_aluOp = `ALU_SLT;
                                                3'b011  : o_aluOp = `ALU_SLTU;
                                                3'b100  : o_aluOp = `ALU_XOR;
                                                3'b101  : o_aluOp = `ALU_SRL;
                                                3'b110  : o_aluOp = `ALU_OR;
                                                3'b111  : o_aluOp = `ALU_AND;
                                                default : o_illegal = 1'b1;
                                        endcase
                                end else if (w_f7Alt && w_funct3 == 3'b000) begin
                                        o_aluOp       = `ALU_SUB;
                                end else if (w_f7Alt && w_funct3 == 3'b101) begin
                                        o_aluOp       = `ALU_SRA;
                                end else begin
                                        o_illegal     = 1'b1;               // includes M-extension (funct7=1)
                                end
                        end
                        // ---------------- FENCE = NOP -----------
                        `OP_FENCE : begin
                                if (w_funct3 != 3'b000) o_illegal = 1'b1;   // FENCE.I not supported
                        end
                        // ---------------- SYSTEM ----------------
                        `OP_SYSTEM : begin
                                case (w_funct3)
                                        3'b000 : begin
                                                if      (i_inst == 32'h0000_0073) o_ecall  = 1'b1;
                                                else if (i_inst == 32'h0010_0073) o_ebreak = 1'b1;
                                                else if (i_inst == 32'h3020_0073) o_mret   = 1'b1;
                                                else                              o_illegal = 1'b1;   // WFI, SRET, ...
                                        end
                                        3'b001, 3'b010, 3'b011,
                                        3'b101, 3'b110, 3'b111 : begin
                                                o_csr         = 1'b1;
                                                o_wbSel       = `WB_CSR;
                                                o_regWrite    = w_rdNz;
                                                o_immType     = `IMM_Z;               // zimm for CSRR*I
                                                // write source : funct3[2] ? zimm : rs1 (selected in EX)
                                                o_useRs1      = ~w_funct3[2];             // register forms read rs1
                                                // read : CSRRW/CSRRWI with rd=x0 does not read
                                                o_csrRe       = (w_funct3[1:0] == `CSR_RW) ? w_rdNz : 1'b1;
                                                // write : RS/RC with rs1=x0 (or zimm=0) do not write
                                                o_csrWe       = (w_funct3[1:0] == `CSR_RW) ? 1'b1 : w_rs1Nz;
                                        end
                                        default : o_illegal = 1'b1;             // 100
                                endcase
                        end
                        default : o_illegal = 1'b1;
                endcase
        end

        // ---------- illegal : kill every side effect ----------
        if (o_illegal) begin
                o_useRs1      = 1'b0;
                o_useRs2      = 1'b0;
                o_regWrite    = 1'b0;
                o_memRead     = 1'b0;
                o_memWrite    = 1'b0;
                o_branch      = 1'b0;
                o_jal         = 1'b0;
                o_jalr        = 1'b0;
                o_csr         = 1'b0;
                o_csrRe       = 1'b0;
                o_csrWe       = 1'b0;
        end
end

endmodule
