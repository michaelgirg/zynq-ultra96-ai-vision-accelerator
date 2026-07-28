module alu #(
    parameter int WIDTH = 32
) (
    input  logic [WIDTH-1:0] op_a,
    input  logic [WIDTH-1:0] op_b,
    input  logic [      3:0] alu_op,
    output logic [WIDTH-1:0] result,
    output logic             zero
);
    import rv32i_pkg::*;

    logic [$clog2(WIDTH)-1:0] shift_amt;

    assign shift_amt = op_b[$clog2(WIDTH)-1:0];

    always_comb begin
        result = '0;

        case (alu_op)
            ALU_ADD:    result = op_a + op_b;
            ALU_SUB:    result = op_a - op_b;
            ALU_SLL:    result = op_a << shift_amt;
            ALU_SRL:    result = op_a >> shift_amt;
            ALU_SRA:    result = $signed(op_a) >>> shift_amt;
            ALU_AND:    result = op_a & op_b;
            ALU_OR:     result = op_a | op_b;
            ALU_XOR:    result = op_a ^ op_b;
            ALU_SLT:    result[0] = $signed(op_a) < $signed(op_b);
            ALU_SLTU:   result[0] = op_a < op_b;
            ALU_COPY_B: result = op_b;
            default:    result = '0;
        endcase
    end

    assign zero = (result == '0);

endmodule
