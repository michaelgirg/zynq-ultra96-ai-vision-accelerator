`timescale 1ns/1ps

module muldiv_unit_tb;
    import rv32i_pkg::*;

    logic        clk;
    logic        rst;
    logic        in_valid;
    logic [ 2:0] funct3;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic        result_ready;
    logic [31:0] result;
    logic        busy;
    logic        done;

    int errors;
    int tests;
    int mul_starts;
    int div_starts;

    muldiv_unit dut (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (in_valid),
        .funct3      (funct3),
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data),
        .result_ready(result_ready),
        .result      (result),
        .busy        (busy),
        .done        (done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Counting the private request strobes makes duplicate execution visible
    // without requiring licensed assertion support.
    always @(posedge clk) begin
        if (dut.mul_start) mul_starts++;
        if (dut.div_start) div_starts++;
    end

    task automatic apply_reset();
        rst          = 1'b1;
        in_valid     = 1'b0;
        funct3       = MULDIV_MUL;
        rs1_data     = '0;
        rs2_data     = '0;
        result_ready = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;
        @(negedge clk);

        if (busy || done || (result !== 32'b0)) begin
            $error("reset state: busy=%b done=%b result=%08h", busy, done, result);
            errors++;
        end
    endtask

    // Keep the completed instruction in EX for several cycles, just as a
    // D-cache miss will. The result must be held and the operation must not be
    // issued again even after the live forwarded operands disappear.
    task automatic check_held_completion(
        input string       test_name,
        input muldiv_op_t  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] expected
    );
        int starts_before;
        int waited;
        logic test_is_div;

        tests++;
        test_is_div  = test_op[2];
        starts_before = test_is_div ? div_starts : mul_starts;

        while (busy) @(negedge clk);

        funct3       = test_op;
        rs1_data     = test_a;
        rs2_data     = test_b;
        result_ready = 1'b0;
        in_valid     = 1'b1;

        waited = 0;
        while (!done && (waited < 50)) begin
            @(negedge clk);
            waited++;
        end

        if (!done) begin
            $error("%s: timed out waiting for completion", test_name);
            errors++;
        end

        if (result !== expected) begin
            $error("%s: expected=%08h actual=%08h", test_name, expected, result);
            errors++;
        end

        // Remove the forwarded operand values while the completed instruction
        // remains held. A duplicate issue would now compute a different result.
        rs1_data = 32'ha5a5_5a5a;
        rs2_data = 32'h0000_0003;

        repeat (4) begin
            @(posedge clk);
            #1;

            if (!done || !busy || (result !== expected)) begin
                $error("%s: held result changed: busy=%b done=%b result=%08h",
                       test_name, busy, done, result);
                errors++;
            end

            if ((test_is_div ? div_starts : mul_starts) != (starts_before + 1)) begin
                $error("%s: operation reissued while result was back-pressured", test_name);
                errors++;
            end
        end

        // Let EX/MEM accept the result. The core changes ID/EX on this edge, so
        // remove in_valid immediately afterward to model that advancement.
        @(negedge clk);
        result_ready = 1'b1;
        @(posedge clk);
        #1;
        in_valid = 1'b0;
        @(negedge clk);

        if (done || busy) begin
            $error("%s: wrapper did not return idle after acceptance", test_name);
            errors++;
        end

        if ((test_is_div ? div_starts : mul_starts) != (starts_before + 1)) begin
            $error("%s: expected exactly one start pulse", test_name);
            errors++;
        end

        result_ready = 1'b0;
    endtask

    task automatic check_immediate_acceptance();
        int starts_before;
        int waited;

        tests++;
        while (busy) @(negedge clk);

        starts_before = mul_starts;
        funct3       = MULDIV_MUL;
        rs1_data     = 32'd9;
        rs2_data     = 32'd7;
        result_ready = 1'b1;
        in_valid     = 1'b1;

        waited = 0;
        while (!done && (waited < 12)) begin
            @(negedge clk);
            waited++;
        end

        if (!done || (result !== 32'd63)) begin
            $error("immediate acceptance: done=%b result=%08h", done, result);
            errors++;
        end

        @(posedge clk);
        #1;
        in_valid = 1'b0;
        @(negedge clk);

        if (done || busy || (mul_starts != (starts_before + 1))) begin
            $error("immediate acceptance did not complete exactly once");
            errors++;
        end

        result_ready = 1'b0;
    endtask

    initial begin
        errors       = 0;
        tests        = 0;
        mul_starts   = 0;
        div_starts   = 0;
        rst          = 1'b0;
        in_valid     = 1'b0;
        funct3       = MULDIV_MUL;
        rs1_data     = '0;
        rs2_data     = '0;
        result_ready = 1'b0;

        apply_reset();
        check_immediate_acceptance();
        check_held_completion("held MUL", MULDIV_MUL, 32'd6, 32'd7, 32'd42);
        check_held_completion("held DIV", MULDIV_DIV, 32'd100, 32'd7, 32'd14);

        if (errors == 0)
            $display("PASS: muldiv_unit_tb (%0d handshake tests)", tests);
        else
            $fatal(1, "FAIL: muldiv_unit_tb had %0d errors", errors);

        $finish;
    end

endmodule
