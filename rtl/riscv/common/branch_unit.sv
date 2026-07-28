// Branch comparison unit.
//
// Compares rs1_data and rs2_data according to branch_op. The supported
// operations are BEQ, BNE, BLT, BGE, BLTU, and BGEU.
//
// NOTE:
// This module only decides whether the branch is taken. It does not calculate
// the target address. The PC logic combines branch_taken with the branch
// immediate to select the next PC.

module branch_unit (
    input  logic [31:0] rs1_data,
    input  logic [31:0] rs2_data,
    input  logic [ 2:0] branch_op,
    output logic        branch_taken
);
    import rv32i_pkg::*;

    always_comb begin
        branch_taken = 1'b0;

        case (branch_op)
            BR_EQ:   branch_taken = (rs1_data == rs2_data);
            BR_NE:   branch_taken = (rs1_data != rs2_data);
            BR_LT:   branch_taken = ($signed(rs1_data) < $signed(rs2_data));
            BR_GE:   branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
            BR_LTU:  branch_taken = (rs1_data < rs2_data);
            BR_GEU:  branch_taken = (rs1_data >= rs2_data);
            BR_NONE: branch_taken = 1'b0;
            default: branch_taken = 1'b0;
        endcase
    end

endmodule
