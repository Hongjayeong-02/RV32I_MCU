`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rv32_lsu  (MEM stage, combinational)
//   Byte-lane handling between the core and a 32-bit word memory (spec 7).
//   store : o_be from size / addr[1:0], store data replicated on every lane
//           (sb -> 4 copies of rs2[7:0], sh -> 2 copies of rs2[15:0])
//   load  : read word shifted by addr[1:0], then sign / zero extended
//   o_misaligned : half on odd address, word on addr[1:0] != 0
//                  (M2 turns it into mcause 4 / 6; be is forced to 0 here)
// -----------------------------------------------------------------------------
module rv32_lsu (
        input   wire    [1:0]   i_addrLo,       // addr[1:0]
        input   wire    [1:0]   i_size,         // 0 byte, 1 half, 2 word
        input   wire            i_unsigned,     // LBU / LHU
        input   wire            i_store,
        input   wire    [31:0]  i_storeData,    // rs2 (forwarded)
        input   wire    [31:0]  i_rdata,        // word from RAM / ROM / APB

        output  reg     [3:0]   o_be,
        output  reg     [31:0]  o_wdata,
        output  reg     [31:0]  o_loadData,
        output  reg             o_misaligned
);

reg     [31:0]  r_shift;

always @(*) begin
        // ---- alignment ----
        case (i_size)
                2'd0    : o_misaligned = 1'b0;
                2'd1    : o_misaligned = i_addrLo[0];
                2'd2    : o_misaligned = (i_addrLo != 2'd0);
                default : o_misaligned = 1'b1;
        endcase

        // ---- store lanes ----
        case (i_size)
                2'd0    : begin
                        o_wdata = {4{i_storeData[7:0]}};
                        o_be    = 4'b0001 << i_addrLo;
                end
                2'd1    : begin
                        o_wdata = {2{i_storeData[15:0]}};
                        o_be    = i_addrLo[1] ? 4'b1100 : 4'b0011;
                end
                default : begin
                        o_wdata = i_storeData;
                        o_be    = 4'b1111;
                end
        endcase
        if (!i_store || o_misaligned) o_be = 4'b0000;

        // ---- load extract ----
        r_shift = i_rdata >> {i_addrLo, 3'b000};
        case (i_size)
                2'd0    : o_loadData = i_unsigned ? {24'd0, r_shift[7:0]}
                                                  : {{24{r_shift[7]}}, r_shift[7:0]};
                2'd1    : o_loadData = i_unsigned ? {16'd0, r_shift[15:0]}
                                                  : {{16{r_shift[15]}}, r_shift[15:0]};
                default : o_loadData = i_rdata;
        endcase
end

endmodule
