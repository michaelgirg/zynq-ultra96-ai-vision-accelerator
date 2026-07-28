import rv32i_pkg::*;

// M-extension execute wrapper.
//
// Sits in the EX stage next to the ALU. When a MUL/DIV-class instruction is in
// EX, this unit runs the operation over one or more cycles and raises `busy`,
// which the core turns into a pipeline stall (freeze PC / IF-ID, hold ID-EX,
// bubble EX/MEM) until `done`. The completed result remains valid until
// `result_ready` says EX/MEM accepted it. This matters when a future cache miss
// holds the pipeline after the arithmetic has finished. The result writes back
// through the normal WB_ALU path, so no new writeback source is needed.
//
// funct3 selects the operation; funct3[2] splits the two sub-units:
//   funct3[2] == 0 -> mul_unit  (MUL, MULH, MULHSU, MULHU)
//   funct3[2] == 1 -> div_unit  (DIV, DIVU, REM, REMU)
//
// Single-issue: this unit handles one op at a time. `in_valid` stays high for
// the whole time the op is held (stalled) in EX, so a private `running` flag,
// not `in_valid`, gates `start`. A second flag holds a completed result that EX
// could not accept. Together they guarantee exactly one start pulse for the
// instruction, even if memory back-pressure keeps that instruction in EX after
// the selected sub-unit finishes.

module muldiv_unit (
    input  logic        clk,
    input  logic        rst,

    input  logic        in_valid,   // a real muldiv instruction is in EX
    input  logic [ 2:0] funct3,     // selects one of the 8 RV32M ops
    input  logic [31:0] rs1_data,   // already-forwarded EX operand a
    input  logic [31:0] rs2_data,   // already-forwarded EX operand b
    input  logic        result_ready, // EX/MEM can accept the completed result

    output logic [31:0] result,
    output logic        busy,       // operation running or result waiting
    output logic        done        // result is valid; may remain high
);

    // running = an operation has been started and has not yet reported done.
    logic running;
    logic sel_div_q;   // which sub-unit the in-flight op was routed to
    logic result_valid_q;
    logic [31:0] result_held_q;

    // Do not issue while a previous result is waiting for EX/MEM. Without this
    // guard, a cache stall could make the completed instruction start again.
    logic issue;
    assign issue = in_valid && !running && !result_valid_q;

    // Sub-unit request strobes (one-cycle pulses).
    logic mul_start;
    logic div_start;
    assign mul_start = issue && !funct3[2];
    assign div_start = issue &&  funct3[2];

    // Sub-unit outputs.
    logic [31:0] mul_result;
    logic        mul_done;
    logic        mul_busy;
    logic [31:0] div_result;
    logic        div_done;
    logic        div_busy;

    mul_unit #(
        .WIDTH(32)
    ) u_mul_unit (
        .clk      (clk),
        .rst      (rst),
        .start    (mul_start),
        .op       (funct3),
        .operand_a(rs1_data),
        .operand_b(rs2_data),
        .result   (mul_result),
        .done     (mul_done),
        .busy     (mul_busy)
    );

    div_unit #(
        .WIDTH(32)
    ) u_div_unit (
        .clk     (clk),
        .rst     (rst),
        .start   (div_start),
        .op      (funct3),
        .dividend(rs1_data),
        .divisor (rs2_data),
        .result  (div_result),
        .done    (div_done),
        .busy    (div_busy)
    );

    // Select the active sub-unit's completion and result.
    logic        sub_done;
    logic        completion;
    logic [31:0] sub_result;
    assign sub_done   = sel_div_q ? div_done   : mul_done;
    assign sub_result = sel_div_q ? div_result : mul_result;
    assign completion = running && sub_done;

    // A result can be consumed directly on the sub-unit's completion cycle. If
    // EX/MEM is blocked, save it and keep done asserted until result_ready.
    assign busy   = running || issue || result_valid_q;
    assign done   = completion || result_valid_q;
    assign result = result_valid_q ? result_held_q : sub_result;

    always_ff @(posedge clk) begin
        if (rst) begin
            running        <= 1'b0;
            sel_div_q      <= 1'b0;
            result_valid_q <= 1'b0;
            result_held_q  <= '0;
        end
        else begin
            if (issue) begin
                running   <= 1'b1;
                sel_div_q <= funct3[2];
            end
            else if (completion) begin
                running <= 1'b0;
            end

            if (completion && !result_ready) begin
                // The producer is done, but EX cannot advance. Save the value
                // because the sub-unit's done pulse disappears next cycle.
                result_valid_q <= 1'b1;
                result_held_q  <= sub_result;
            end
            else if (result_valid_q && result_ready) begin
                // EX/MEM accepted the held result and this instruction may
                // finally leave the Execute stage.
                result_valid_q <= 1'b0;
            end
        end
    end

endmodule
