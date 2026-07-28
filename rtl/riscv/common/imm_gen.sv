//Immediate Generator

// This will extract and rebuild the immediate value from a 32-bit instruction
// The output immediate is a 32-bit sign extended value, except for U-type where the lower 12 bits are filled
// with zeroes. This immediate can be used for ALU operations, mem addr, branch offsets, or jump targets
module imm_gen (
    input  logic [31:0] instruction,
    input  logic [ 2:0] imm_sel,
    output logic [31:0] immediate
);
    import rv32i_pkg::*;

    always_comb begin
        immediate = '0;

        case (imm_sel)
            IMM_I: begin
                immediate = {{20{instruction[31]}}, instruction[31:20]};
            end

            IMM_S: begin
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            IMM_B: begin
                immediate = {
                    {19{instruction[31]}},
                    instruction[31],
                    instruction[7],
                    instruction[30:25],
                    instruction[11:8],
                    1'b0
                };
            end

            IMM_U: begin
                immediate = {instruction[31:12], 12'b0};
            end

            IMM_J: begin
                immediate = {
                    {11{instruction[31]}},
                    instruction[31],
                    instruction[19:12],
                    instruction[20],
                    instruction[30:21],
                    1'b0
                };
            end

            default: begin
                immediate = '0;
            end
        endcase
    end

endmodule
