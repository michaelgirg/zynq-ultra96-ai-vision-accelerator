import rv32i_pkg::*;

// =============================================================================
// div_unit.sv -- iterative RV32M divider
// -----------------------------------------------------------------------------
// Supported instructions (op carries the funct3 of the divide variant):
//   funct3 100 DIV   signed   quotient
//   funct3 101 DIVU  unsigned quotient
//   funct3 110 REM   signed   remainder
//   funct3 111 REMU  unsigned remainder
//
// RISC-V mandates results for the corner cases (NO trap is taken):
//   divide by zero      : DIV/DIVU -> -1 / 0xFFFF_FFFF, REM/REMU -> dividend
//   signed overflow      : (-2^31 / -1) quotient -> -2^31, remainder -> 0
//
// Handshake (matches mul_unit):
//   start : 1-cycle pulse accepted when busy is low; latches operands/op.
//   busy  : high while the operation is in flight (including the done cycle),
//           so the processor can hold the instruction in Execute.
//   done  : 1-cycle pulse when `result` is valid.
//
// Implementation: operands are reduced to magnitudes, a restoring shift/subtract
// loop runs WIDTH iterations building quotient and remainder together, then the
// result sign is applied. Corner cases skip the loop and finish immediately.
//
//   IDLE ---start---> ITER (WIDTH cycles) ---> FINISH (done) ---> IDLE
//        \----------corner case----------------^
// =============================================================================

module div_unit #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             rst,

    input  logic             start,
    input  logic [      2:0] op,        // funct3 of the divide variant
    input  logic [WIDTH-1:0] dividend,  // rs1
    input  logic [WIDTH-1:0] divisor,   // rs2

    output logic [WIDTH-1:0] result,
    output logic             done,
    output logic             busy
);

    // Counter wide enough to hold the value WIDTH (0..WIDTH).
    localparam int CNT_W = $clog2(WIDTH + 1) + 1;

    typedef enum logic [1:0] {
        S_IDLE,
        S_ITER,
        S_FINISH
    } div_state_t;

    div_state_t state;

    // -------------------------------------------------------------------------
    // Working registers (all values below are unsigned magnitudes)
    // -------------------------------------------------------------------------
    // quotient_q starts as the dividend magnitude; each iteration shifts one bit
    // of it out of the top into the partial remainder and shifts one quotient
    // bit in at the bottom. remainder_q is the running partial remainder.
    logic [WIDTH-1:0] quotient_q;
    logic [WIDTH-1:0] remainder_q;
    logic [WIDTH-1:0] divisor_mag_q;
    logic [CNT_W-1:0] count_q;

    // Sign fix-up flags captured when the operation is accepted.
    logic       quot_neg_q;   // final quotient  should be negated
    logic       rem_neg_q;    // final remainder should be negated
    logic [2:0] op_q;

    // busy stays high from the first ITER cycle through FINISH so the pipeline
    // remains stalled until done is observed. done and result are both valid
    // during the single FINISH cycle, while busy is still high.
    assign busy = (state != S_IDLE);
    assign done = (state == S_FINISH);

    // -------------------------------------------------------------------------
    // Accept-time operand analysis (combinational, sampled only in S_IDLE)
    // -------------------------------------------------------------------------
    logic             is_signed_op;
    logic             dividend_sign;
    logic             divisor_sign;
    logic [WIDTH-1:0] dividend_mag;
    logic [WIDTH-1:0] divisor_mag;
    logic             is_div_result;   // op selects a quotient (vs remainder)
    logic             div_by_zero;
    logic             signed_overflow;

    always_comb begin
        is_signed_op  = (op == MULDIV_DIV) || (op == MULDIV_REM);
        dividend_sign = is_signed_op && dividend[WIDTH-1];
        divisor_sign  = is_signed_op && divisor[WIDTH-1];

        // abs(): magnitude of -2^31 is 2^31, which fits unsigned WIDTH bits.
        dividend_mag  = dividend_sign ? (~dividend + 1'b1) : dividend;
        divisor_mag   = divisor_sign  ? (~divisor  + 1'b1) : divisor;

        is_div_result = (op == MULDIV_DIV) || (op == MULDIV_DIVU);

        div_by_zero     = (divisor == '0);
        signed_overflow = is_signed_op &&
                          (dividend == {1'b1, {(WIDTH-1){1'b0}}}) &&  // -2^31
                          (&divisor);                                 // -1
    end

    // -------------------------------------------------------------------------
    // One restoring shift/subtract step (combinational, used in S_ITER)
    // -------------------------------------------------------------------------
    logic [WIDTH:0]   rem_ext;   // partial remainder shifted left by one bit
    logic [WIDTH:0]   rem_sub;
    logic [WIDTH-1:0] remainder_next;
    logic [WIDTH-1:0] quotient_next;

    always_comb begin
        rem_ext = {remainder_q, quotient_q[WIDTH-1]};
        rem_sub = rem_ext - {1'b0, divisor_mag_q};

        if (rem_ext >= {1'b0, divisor_mag_q}) begin
            remainder_next = rem_sub[WIDTH-1:0];
            quotient_next  = {quotient_q[WIDTH-2:0], 1'b1};
        end
        else begin
            remainder_next = rem_ext[WIDTH-1:0];
            quotient_next  = {quotient_q[WIDTH-2:0], 1'b0};
        end
    end

    // Apply the captured sign to the freshly computed magnitudes.
    logic             is_div_result_q;
    logic [WIDTH-1:0] final_quotient;
    logic [WIDTH-1:0] final_remainder;

    always_comb begin
        is_div_result_q = (op_q == MULDIV_DIV) || (op_q == MULDIV_DIVU);
        final_quotient  = quot_neg_q ? (~quotient_next  + 1'b1) : quotient_next;
        final_remainder = rem_neg_q  ? (~remainder_next + 1'b1) : remainder_next;
    end

    // -------------------------------------------------------------------------
    // Control / datapath FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            quotient_q    <= '0;
            remainder_q   <= '0;
            divisor_mag_q <= '0;
            count_q       <= '0;
            quot_neg_q    <= 1'b0;
            rem_neg_q     <= 1'b0;
            op_q          <= MULDIV_DIV;
            result        <= '0;
        end
        else begin
            case (state)
                // -------------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        op_q       <= op;
                        quot_neg_q <= dividend_sign ^ divisor_sign;
                        rem_neg_q  <= dividend_sign;

                        if (div_by_zero) begin
                            // DIV/DIVU -> all ones (-1); REM/REMU -> dividend.
                            result <= is_div_result ? {WIDTH{1'b1}} : dividend;
                            state  <= S_FINISH;
                        end
                        else if (signed_overflow) begin
                            // quotient -> -2^31; remainder -> 0.
                            result <= is_div_result ? {1'b1, {(WIDTH-1){1'b0}}}
                                                    : '0;
                            state  <= S_FINISH;
                        end
                        else begin
                            quotient_q    <= dividend_mag;
                            remainder_q   <= '0;
                            divisor_mag_q <= divisor_mag;
                            count_q       <= CNT_W'(WIDTH);
                            state         <= S_ITER;
                        end
                    end
                end

                // -------------------------------------------------------------
                S_ITER: begin
                    quotient_q  <= quotient_next;
                    remainder_q <= remainder_next;
                    count_q     <= count_q - 1'b1;

                    // count_q == 1 is the last of the WIDTH iterations; capture
                    // the final result from the just-computed *_next values.
                    if (count_q == 1) begin
                        result <= is_div_result_q ? final_quotient
                                                  : final_remainder;
                        state  <= S_FINISH;
                    end
                end

                // -------------------------------------------------------------
                S_FINISH: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
