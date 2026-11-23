// ---------------------------------------------------------------
// rv32_defs.vh : shared encodings for RV32I MCU core
// ---------------------------------------------------------------
`ifndef RV32_DEFS_VH
`define RV32_DEFS_VH

// ---- opcodes (inst[6:0]) ----
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_IMM      7'b0010011
`define OP_REG      7'b0110011
`define OP_FENCE    7'b0001111
`define OP_SYSTEM   7'b1110011

// ---- ALU operations ----
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_SLL     4'd2
`define ALU_SLT     4'd3
`define ALU_SLTU    4'd4
`define ALU_XOR     4'd5
`define ALU_SRL     4'd6
`define ALU_SRA     4'd7
`define ALU_OR      4'd8
`define ALU_AND     4'd9
`define ALU_PASSB   4'd10   // LUI : result = operand B (imm)

// ---- ALU operand A select ----
`define ASRC_RS1    2'd0
`define ASRC_PC     2'd1
`define ASRC_ZERO   2'd2

// ---- ALU operand B select ----
`define BSRC_RS2    1'b0
`define BSRC_IMM    1'b1

// ---- immediate types ----
`define IMM_I       3'd0
`define IMM_S       3'd1
`define IMM_B       3'd2
`define IMM_U       3'd3
`define IMM_J       3'd4
`define IMM_Z       3'd5    // CSR zimm = inst[19:15] zero-extended

// ---- write-back select ----
`define WB_ALU      2'd0
`define WB_MEM      2'd1
`define WB_PC4      2'd2
`define WB_CSR      2'd3

// ---- CSR command (funct3[1:0]) ----
`define CSR_RW      2'd1
`define CSR_RS      2'd2
`define CSR_RC      2'd3

`endif
