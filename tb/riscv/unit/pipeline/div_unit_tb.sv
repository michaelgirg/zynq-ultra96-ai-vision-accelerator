`timescale 1ns/1ps

module div_unit_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    import rv32i_pkg::*;

    logic        clk;
    logic        rst;
    logic        start;
    logic [2:0]  op;
    logic [31:0] dividend;
    logic [31:0] divisor;
    logic [31:0] result;
    logic        done;
    logic        busy;

    int errors;
    int tests;

    div_unit #(
        .WIDTH(32)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .op      (op),
        .dividend(dividend),
        .divisor (divisor),
        .result  (result),
        .done    (done),
        .busy    (busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Golden model of the RV32M divide semantics, including the mandated corner
    // cases. SystemVerilog signed / and % truncate toward zero, matching the
    // ISA definition of DIV and REM.
    function automatic logic [31:0] reference_result(
        input logic [2:0]  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b
    );
        logic signed [31:0] sa;
        logic signed [31:0] sb;
        sa = test_a;
        sb = test_b;

        case (test_op)
            MULDIV_DIV: begin
                if (test_b == 32'h0000_0000)
                    reference_result = 32'hffff_ffff;                 // -1
                else if ((test_a == 32'h8000_0000) && (test_b == 32'hffff_ffff))
                    reference_result = 32'h8000_0000;                 // overflow
                else
                    reference_result = sa / sb;
            end

            MULDIV_DIVU: begin
                if (test_b == 32'h0000_0000)
                    reference_result = 32'hffff_ffff;
                else
                    reference_result = test_a / test_b;
            end

            MULDIV_REM: begin
                if (test_b == 32'h0000_0000)
                    reference_result = test_a;                        // dividend
                else if ((test_a == 32'h8000_0000) && (test_b == 32'hffff_ffff))
                    reference_result = 32'h0000_0000;                 // overflow
                else
                    reference_result = sa % sb;
            end

            MULDIV_REMU: begin
                if (test_b == 32'h0000_0000)
                    reference_result = test_a;
                else
                    reference_result = test_a % test_b;
            end

            default: reference_result = '0;
        endcase
    endfunction

    task automatic apply_reset();
        start    = 1'b0;
        op       = MULDIV_DIV;
        dividend = '0;
        divisor  = '0;
        rst      = 1'b1;

        repeat (2) @(negedge clk);

        if ((busy !== 1'b0) || (done !== 1'b0) || (result !== 32'b0)) begin
            $error("reset state: expected busy/done/result=0/0/00000000, actual=%b/%b/%08h",
                   busy, done, result);
            errors++;
        end

        rst = 1'b0;
        @(negedge clk);
    endtask

    // Issue one divide, prove operand latching by scribbling on the inputs after
    // acceptance, poll the variable-latency handshake for done, and check the
    // result and the single-cycle done pulse.
    task automatic check_operation(
        input string test_name,
        input logic [2:0]  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b
    );
        logic [31:0] expected;

        expected = reference_result(test_op, test_a, test_b);
        tests++;

        // Wait until the unit is idle before issuing.
        while (busy) @(negedge clk);

        // Present the request and pulse start for exactly one clock.
        @(negedge clk);
        op       = test_op;
        dividend = test_a;
        divisor  = test_b;
        start    = 1'b1;

        @(posedge clk);           // acceptance edge

        // Deassert start and corrupt the inputs to prove the unit uses its
        // latched operands, not the live bus.
        @(negedge clk);
        start    = 1'b0;
        op       = MULDIV_MUL;
        dividend = 32'ha5a5_5a5a;
        divisor  = 32'h5a5a_a5a5;

        // Poll (mid-cycle, where signals are stable) until the result is ready.
        while (!done) @(negedge clk);

        if (busy !== 1'b1) begin
            $error("%s: busy must stay high during the done cycle", test_name);
            errors++;
        end

        if (result !== expected) begin
            $error("%s: op=%03b a=%08h b=%08h expected=%08h actual=%08h",
                   test_name, test_op, test_a, test_b, expected, result);
            errors++;
        end

        // done must be a single-cycle pulse and the unit must return to idle.
        @(negedge clk);
        if ((done !== 1'b0) || (busy !== 1'b0)) begin
            $error("%s: expected idle after completion, busy/done=%b/%b",
                   test_name, busy, done);
            errors++;
        end
    endtask

    // A start received while the divider is running must be ignored: it must not
    // restart the loop or corrupt the in-flight result.
    task automatic check_start_while_busy();
        logic [31:0] expected_first;

        expected_first = reference_result(MULDIV_DIV, 32'd100, 32'd7);
        tests++;

        while (busy) @(negedge clk);

        @(negedge clk);
        op       = MULDIV_DIV;
        dividend = 32'd100;
        divisor  = 32'd7;
        start    = 1'b1;

        @(posedge clk);           // acceptance

        // Hold start high with a different request while busy.
        @(negedge clk);
        op       = MULDIV_DIVU;
        dividend = 32'hffff_ffff;
        divisor  = 32'd2;
        start    = 1'b1;

        while (!done) @(negedge clk);
        start = 1'b0;   // deassert before the unit returns to idle

        if (result !== expected_first) begin
            $error("start while busy replaced the active op: expected=%08h actual=%08h",
                   expected_first, result);
            errors++;
        end

        @(negedge clk);
    endtask

    // Reset asserted mid-divide must cancel the operation and clear the result.
    task automatic check_reset_during_operation();
        tests++;

        while (busy) @(negedge clk);

        @(negedge clk);
        op       = MULDIV_DIV;
        dividend = 32'h1234_5678;
        divisor  = 32'd3;
        start    = 1'b1;

        @(posedge clk);           // acceptance
        @(negedge clk);
        start = 1'b0;

        // Interrupt partway through the iteration loop.
        repeat (4) @(negedge clk);
        rst = 1'b1;
        @(negedge clk);

        if ((busy !== 1'b0) || (done !== 1'b0) || (result !== 32'b0)) begin
            $error("reset during operation: expected busy/done/result=0/0/0, actual=%b/%b/%08h",
                   busy, done, result);
            errors++;
        end

        rst = 1'b0;
        @(negedge clk);
    endtask

    initial begin
        errors = 0;
        tests  = 0;
        rst    = 1'b0;
        start  = 1'b0;
        op     = MULDIV_DIV;
        dividend = '0;
        divisor  = '0;

        apply_reset();

        // ---- DIV (signed quotient) -----------------------------------------
        check_operation("DIV pos/pos",        MULDIV_DIV, 32'd7, 32'd3);
        check_operation("DIV neg/pos",        MULDIV_DIV, -32'd7, 32'd3);
        check_operation("DIV pos/neg",        MULDIV_DIV, 32'd7, -32'd3);
        check_operation("DIV neg/neg",        MULDIV_DIV, -32'd7, -32'd3);
        check_operation("DIV divisor>dividend",MULDIV_DIV, 32'd3, 32'd7);
        check_operation("DIV by zero",        MULDIV_DIV, 32'd42, 32'd0);
        check_operation("DIV overflow",       MULDIV_DIV, 32'h8000_0000, 32'hffff_ffff);
        check_operation("DIV min by one",     MULDIV_DIV, 32'h8000_0000, 32'd1);

        // ---- DIVU (unsigned quotient) --------------------------------------
        check_operation("DIVU small",         MULDIV_DIVU, 32'd7, 32'd3);
        check_operation("DIVU max/2",         MULDIV_DIVU, 32'hffff_ffff, 32'd2);
        check_operation("DIVU by zero",       MULDIV_DIVU, 32'd42, 32'd0);
        check_operation("DIVU high dividend", MULDIV_DIVU, 32'h8000_0000, 32'd3);

        // ---- REM (signed remainder) ----------------------------------------
        check_operation("REM pos/pos",        MULDIV_REM, 32'd7, 32'd3);
        check_operation("REM neg/pos",        MULDIV_REM, -32'd7, 32'd3);
        check_operation("REM pos/neg",        MULDIV_REM, 32'd7, -32'd3);
        check_operation("REM neg/neg",        MULDIV_REM, -32'd7, -32'd3);
        check_operation("REM by zero",        MULDIV_REM, 32'hdead_beef, 32'd0);
        check_operation("REM overflow",       MULDIV_REM, 32'h8000_0000, 32'hffff_ffff);

        // ---- REMU (unsigned remainder) -------------------------------------
        check_operation("REMU small",         MULDIV_REMU, 32'd7, 32'd3);
        check_operation("REMU exact",         MULDIV_REMU, 32'd9, 32'd3);
        check_operation("REMU by zero",       MULDIV_REMU, 32'hdead_beef, 32'd0);
        check_operation("REMU max",           MULDIV_REMU, 32'hffff_ffff, 32'hffff_fffe);

        check_start_while_busy();
        check_reset_during_operation();

        // Confirm normal operation resumes after the cancellation test.
        check_operation("DIV after reset",    MULDIV_DIV, 32'd1000, 32'd13);

        // ---- Constrained-random cross-check against the golden model -------
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_a;
            logic [31:0] random_b;
            logic [2:0]  random_op;

            random_a  = $urandom;
            random_b  = $urandom;
            random_op = $urandom_range(MULDIV_DIV, MULDIV_REMU);

            check_operation($sformatf("random divide %0d", i),
                            random_op, random_a, random_b);
        end

        if (errors == 0) begin
            $display("PASS: div_unit_tb (%0d operations)", tests);
        end
        else begin
            $fatal(1, "FAIL: div_unit_tb had %0d errors across %0d operations",
                   errors, tests);
        end

        $finish;
    end

endmodule
