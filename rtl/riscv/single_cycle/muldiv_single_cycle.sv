import rv32i_pkg::*;

// Combinational RV32M execution unit for the single-cycle core.
//
// Every operation finishes within the current clock period. This keeps the
// core single-cycle, but multiplication and especially division will create a
// long combinational path. The pipelined core uses separate functional units
// so it can adopt multi-cycle implementations later.
//
// RISC-V defines divide-by-zero and signed-overflow results. Neither condition
// raises a trap, so this module returns the required architectural value.

module muldiv_single_cycle #(
    parameter int WIDTH = 32
) (
    input  muldiv_op_t       op,
    input  logic [WIDTH-1:0] operand_a,
    input  logic [WIDTH-1:0] operand_b,
    output logic [WIDTH-1:0] result
);

    localparam logic [WIDTH-1:0] SIGNED_MIN = {
        1'b1,
        {(WIDTH - 1){1'b0}}
    };

    localparam logic [WIDTH-1:0] NEGATIVE_ONE = {WIDTH{1'b1}};

    // The extra extension bit allows every multiply variant to use signed
    // multiplication without losing the meaning of an unsigned operand.
    logic signed [WIDTH:0] signed_a_extended;
    logic signed [WIDTH:0] signed_b_extended;
    logic signed [WIDTH:0] unsigned_a_extended;
    logic signed [WIDTH:0] unsigned_b_extended;

    // Multiplying two (WIDTH + 1)-bit values produces 2*(WIDTH + 1) bits.
    logic signed [(2 * WIDTH) + 1:0] signed_product;
    logic signed [(2 * WIDTH) + 1:0] signed_unsigned_product;
    logic signed [(2 * WIDTH) + 1:0] unsigned_product;

    always_comb begin
        signed_a_extended   = {operand_a[WIDTH-1], operand_a};
        signed_b_extended   = {operand_b[WIDTH-1], operand_b};
        unsigned_a_extended = {1'b0, operand_a};
        unsigned_b_extended = {1'b0, operand_b};

        signed_product = signed_a_extended * signed_b_extended;
        signed_unsigned_product = signed_a_extended * unsigned_b_extended;
        unsigned_product = unsigned_a_extended * unsigned_b_extended;

        result = '0;

        case (op)
            MULDIV_MUL: begin
                // Signedness does not affect the low WIDTH product bits.
                result = unsigned_product[WIDTH-1:0];
            end

            MULDIV_MULH: begin
                result = signed_product[(2 * WIDTH)-1:WIDTH];
            end

            MULDIV_MULHSU: begin
                result = signed_unsigned_product[(2 * WIDTH)-1:WIDTH];
            end

            MULDIV_MULHU: begin
                result = unsigned_product[(2 * WIDTH)-1:WIDTH];
            end

            MULDIV_DIV: begin
                // Signed division truncates toward zero.
                if (operand_b == '0) result = '1;
                else if ((operand_a == SIGNED_MIN) &&
                         (operand_b == NEGATIVE_ONE)) result = SIGNED_MIN;
                else result = $signed(operand_a) / $signed(operand_b);
            end

            MULDIV_DIVU: begin
                if (operand_b == '0) result = '1;
                else result = $unsigned(operand_a) / $unsigned(operand_b);
            end

            MULDIV_REM: begin
                if (operand_b == '0) result = operand_a;
                else if ((operand_a == SIGNED_MIN) &&
                         (operand_b == NEGATIVE_ONE)) result = '0;
                else result = $signed(operand_a) % $signed(operand_b);
            end

            MULDIV_REMU: begin
                if (operand_b == '0) result = operand_a;
                else result = $unsigned(operand_a) % $unsigned(operand_b);
            end

            default: result = '0;
        endcase
    end

endmodule
