import rv32i_pkg::*;

// =============================================================================
// mul_unit.sv -- pipelined RV32M multiplier
// -----------------------------------------------------------------------------
// Supported instructions:
//   MUL     : lower 32 bits of signed/unsigned multiplication
//   MULH    : upper 32 bits of signed   * signed
//   MULHSU  : upper 32 bits of signed   * unsigned
//   MULHU   : upper 32 bits of unsigned * unsigned
//
// Pipeline operation:
//   Stage 1: Save the operands, operation, and correct signedness.
//   Stage 2: Calculate and save the complete product.
//   Output : Select the upper or lower 32 bits and pulse done.
//
// The unit accepts a request when start is high and busy is low. While an
// operation is moving through the multiplier, busy remains high so the
// processor can hold the instruction in the Execute stage.
// =============================================================================

module mul_unit #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             rst,

    input  logic             start,
    input  logic [      2:0] op,
    input  logic [WIDTH-1:0] operand_a,
    input  logic [WIDTH-1:0] operand_b,

    output logic [WIDTH-1:0] result,
    output logic             done,
    output logic             busy
);

    // -------------------------------------------------------------------------
    // Stage 1: Operand preparation
    // -------------------------------------------------------------------------

    // The extra upper bit controls whether each operand is interpreted as
    // signed or unsigned by the multiplication operator.
    logic signed [WIDTH:0] operand_a_q;
    logic signed [WIDTH:0] operand_b_q;

    logic [2:0] op_q;
    logic       stage_one_valid;

    // -------------------------------------------------------------------------
    // Stage 2: Full product (compute and register full product)
    // -------------------------------------------------------------------------

    // Multiplying two (WIDTH + 1)-bit operands creates a
    // 2 * (WIDTH + 1)-bit result. For WIDTH = 32, this is 66 bits.
    logic signed [(2 * WIDTH) + 1:0] product_q;

    logic [2:0] op_product_q;
    logic       stage_two_valid;

    // The unit is busy whenever an operation is inside either pipeline stage.
    assign busy = stage_one_valid || stage_two_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            operand_a_q    <= '0;
            operand_b_q    <= '0;
            op_q           <= MULDIV_MUL;
            stage_one_valid <= 1'b0;

            product_q       <= '0;
            op_product_q    <= MULDIV_MUL;
            stage_two_valid <= 1'b0;

            result <= '0;
            done   <= 1'b0;
        end
        else begin
            // done is high for exactly one cycle when Stage 2 completes.
            done <= stage_two_valid;

            // Move the valid bit through the multiplier pipeline.
            stage_two_valid <= stage_one_valid;
            stage_one_valid <= 1'b0;

            // -----------------------------------------------------------------
            // Stage 1 -> Stage 2
            // -----------------------------------------------------------------
            // The multiplication happens between the Stage 1 and Stage 2
            // registers. This breaks the multiplier out of the processor's
            // complete single-cycle Execute path.
            if (stage_one_valid) begin
                product_q    <= operand_a_q * operand_b_q;
                op_product_q <= op_q;
            end

            // -----------------------------------------------------------------
            // Stage 2 -> Output
            // -----------------------------------------------------------------
            if (stage_two_valid) begin
                case (op_product_q)
                    MULDIV_MUL: //returns the lower WIDTH bits
                        result <= product_q[WIDTH-1:0];

                    MULDIV_MULH, //returns the upper 32 bits
                    MULDIV_MULHSU,
                    MULDIV_MULHU:
                        result <= product_q[(2 * WIDTH)-1:WIDTH];

                    default:
                        result <= '0;
                endcase
            end

            // -----------------------------------------------------------------
            // Accept a new multiplication
            // -----------------------------------------------------------------
            if (start && !busy) begin
                op_q            <= op;
                stage_one_valid <= 1'b1;

                case (op)
                    MULDIV_MUL,
                    MULDIV_MULH: begin
                        // MULH is signed * signed. MUL may use the same
                        // extension because signedness does not change the
                        // lower WIDTH bits of the product.
                        operand_a_q <= {operand_a[WIDTH-1], operand_a};
                        operand_b_q <= {operand_b[WIDTH-1], operand_b};
                    end

                    MULDIV_MULHSU: begin
                        // First operand signed, second operand unsigned.
                        operand_a_q <= {operand_a[WIDTH-1], operand_a};
                        operand_b_q <= {1'b0, operand_b};
                    end

                    MULDIV_MULHU: begin
                        // Both operands unsigned.
                        operand_a_q <= {1'b0, operand_a};
                        operand_b_q <= {1'b0, operand_b};
                    end

                    default: begin
                        operand_a_q <= '0;
                        operand_b_q <= '0;
                    end
                endcase
            end
        end
    end

endmodule
