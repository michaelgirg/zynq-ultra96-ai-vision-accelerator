`timescale 1ns/1ps

module mul_unit_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    import rv32i_pkg::*;

    logic        clk;
    logic        rst;
    logic        start;
    logic [2:0]  op;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;
    logic        done;
    logic        busy;

    int errors;
    int tests;

    mul_unit dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .op       (op),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result   (result),
        .done     (done),
        .busy     (busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Calculate the architectural RV32M result independently from the DUT's
    // registered datapath. The extra bit keeps unsigned values positive when
    // they are used by SystemVerilog's signed multiplication operator.
    function automatic logic [31:0] reference_result(
        input logic [2:0]  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b
    );
        logic signed [32:0] signed_a_extended;
        logic signed [32:0] signed_b_extended;
        logic signed [32:0] unsigned_a_extended;
        logic signed [32:0] unsigned_b_extended;
        logic signed [65:0] signed_product;
        logic signed [65:0] signed_unsigned_product;
        logic signed [65:0] unsigned_product;

        signed_a_extended   = {test_a[31], test_a};
        signed_b_extended   = {test_b[31], test_b};
        unsigned_a_extended = {1'b0, test_a};
        unsigned_b_extended = {1'b0, test_b};

        signed_product          = signed_a_extended * signed_b_extended;
        signed_unsigned_product = signed_a_extended * unsigned_b_extended;
        unsigned_product        = unsigned_a_extended * unsigned_b_extended;

        case (test_op)
            MULDIV_MUL:    reference_result = unsigned_product[31:0];
            MULDIV_MULH:   reference_result = signed_product[63:32];
            MULDIV_MULHSU: reference_result = signed_unsigned_product[63:32];
            MULDIV_MULHU:  reference_result = unsigned_product[63:32];
            default:       reference_result = '0;
        endcase
    endfunction

    task automatic report_protocol_error(
        input string test_name,
        input string phase,
        input logic expected_busy,
        input logic expected_done
    );
        if ((busy !== expected_busy) || (done !== expected_done)) begin
            $error(
                "%s during %s: expected busy/done=%b/%b, actual=%b/%b",
                test_name,
                phase,
                expected_busy,
                expected_done,
                busy,
                done
            );
            errors++;
        end
    endtask

    task automatic apply_reset();
        start     = 1'b0;
        op        = MULDIV_MUL;
        operand_a = '0;
        operand_b = '0;
        rst       = 1'b1;

        repeat (2) @(posedge clk);
        #1;

        if ((busy !== 1'b0) || (done !== 1'b0) || (result !== 32'b0)) begin
            $error(
                "reset state: expected busy/done/result=0/0/00000000, actual=%b/%b/%08h",
                busy,
                done,
                result
            );
            errors++;
        end

        @(negedge clk);
        rst = 1'b0;
    endtask

    // Submit one request and verify every cycle of the fixed-latency
    // handshake. Inputs are deliberately changed after acceptance to prove
    // that the multiplier uses its saved operands and operation.
    task automatic check_operation(
        input string test_name,
        input logic [2:0]  test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b
    );
        logic [31:0] expected;

        expected = reference_result(test_op, test_a, test_b);
        tests++;

        while (busy) @(negedge clk);

        @(negedge clk);
        op        = test_op;
        operand_a = test_a;
        operand_b = test_b;
        start     = 1'b1;

        // Request accepted into Stage 1.
        @(posedge clk);
        #1;
        report_protocol_error(test_name, "operand stage", 1'b1, 1'b0);

        @(negedge clk);
        start     = 1'b0;
        op        = MULDIV_DIV;
        operand_a = 32'ha5a5_5a5a;
        operand_b = 32'h5a5a_a5a5;

        // Product registered in Stage 2.
        @(posedge clk);
        #1;
        report_protocol_error(test_name, "product stage", 1'b1, 1'b0);

        // Result becomes valid exactly two clocks after acceptance.
        @(posedge clk);
        #1;
        report_protocol_error(test_name, "completion", 1'b0, 1'b1);

        if (result !== expected) begin
            $error(
                "%s: op=%03b a=%08h b=%08h expected=%08h actual=%08h",
                test_name,
                test_op,
                test_a,
                test_b,
                expected,
                result
            );
            errors++;
        end

        // done must be a pulse, not a level that remains asserted.
        @(posedge clk);
        #1;
        report_protocol_error(test_name, "cycle after completion", 1'b0, 1'b0);
    endtask

    // A start received while busy must not replace the operation already in
    // the multiplier or create a second completion pulse later.
    task automatic check_start_while_busy();
        logic [31:0] expected_first;

        expected_first = reference_result(
            MULDIV_MULH,
            32'h8000_0000,
            32'hffff_fffd
        );
        tests++;

        @(negedge clk);
        op        = MULDIV_MULH;
        operand_a = 32'h8000_0000;
        operand_b = 32'hffff_fffd;
        start     = 1'b1;

        @(posedge clk);
        #1;
        report_protocol_error("start while busy", "first acceptance", 1'b1, 1'b0);

        // Attempt to replace the active request with a different operation.
        @(negedge clk);
        op        = MULDIV_MULHU;
        operand_a = 32'hffff_ffff;
        operand_b = 32'hffff_ffff;
        start     = 1'b1;

        @(posedge clk);
        #1;
        report_protocol_error("start while busy", "rejected request", 1'b1, 1'b0);

        @(negedge clk);
        start = 1'b0;

        @(posedge clk);
        #1;
        report_protocol_error("start while busy", "first completion", 1'b0, 1'b1);

        if (result !== expected_first) begin
            $error(
                "start while busy replaced active operation: expected=%08h actual=%08h",
                expected_first,
                result
            );
            errors++;
        end

        // The rejected request must not produce a delayed completion.
        repeat (2) begin
            @(posedge clk);
            #1;
            report_protocol_error("start while busy", "no phantom result", 1'b0, 1'b0);
        end
    endtask

    // Reset must cancel an operation in either pipeline stage. This test
    // resets after acceptance and confirms that no stale result appears.
    task automatic check_reset_during_operation();
        tests++;

        @(negedge clk);
        op        = MULDIV_MULHU;
        operand_a = 32'hffff_ffff;
        operand_b = 32'hffff_ffff;
        start     = 1'b1;

        @(posedge clk);
        #1;
        report_protocol_error("reset during operation", "before reset", 1'b1, 1'b0);

        @(negedge clk);
        start = 1'b0;
        rst   = 1'b1;

        @(posedge clk);
        #1;
        report_protocol_error("reset during operation", "reset", 1'b0, 1'b0);

        if (result !== 32'b0) begin
            $error("reset during operation did not clear result: actual=%08h", result);
            errors++;
        end

        @(negedge clk);
        rst = 1'b0;

        repeat (3) begin
            @(posedge clk);
            #1;
            report_protocol_error("reset during operation", "cancelled request", 1'b0, 1'b0);
        end
    endtask

    initial begin
        errors = 0;
        tests  = 0;
        rst    = 1'b0;
        start  = 1'b0;
        op     = MULDIV_MUL;
        operand_a = '0;
        operand_b = '0;

        apply_reset();

        // Directed arithmetic cases cover zeros, sign boundaries, overflow
        // in the low half, and products whose upper half is significant.
        check_operation("MUL zero", MULDIV_MUL,
                        32'h0000_0000, 32'hffff_ffff);
        check_operation("MUL positive", MULDIV_MUL,
                        32'd7, 32'd9);
        check_operation("MUL negative", MULDIV_MUL,
                        32'hffff_fffe, 32'd3);
        check_operation("MUL low overflow", MULDIV_MUL,
                        32'h8000_0000, 32'd2);

        check_operation("MULH negative", MULDIV_MULH,
                        32'hffff_fffe, 32'd3);
        check_operation("MULH minimum", MULDIV_MULH,
                        32'h8000_0000, 32'd2);
        check_operation("MULH positive maximum", MULDIV_MULH,
                        32'h7fff_ffff, 32'h7fff_ffff);

        check_operation("MULHSU negative by unsigned maximum", MULDIV_MULHSU,
                        32'hffff_fffe, 32'hffff_ffff);
        check_operation("MULHSU positive by unsigned maximum", MULDIV_MULHSU,
                        32'h7fff_ffff, 32'hffff_ffff);
        check_operation("MULHSU minimum by two", MULDIV_MULHSU,
                        32'h8000_0000, 32'd2);

        check_operation("MULHU maximum", MULDIV_MULHU,
                        32'hffff_ffff, 32'hffff_ffff);
        check_operation("MULHU high bit", MULDIV_MULHU,
                        32'h8000_0000, 32'd2);
        check_operation("MULHU by one", MULDIV_MULHU,
                        32'hffff_ffff, 32'd1);

        // Unsupported divide funct3 values are routed to div_unit by the
        // wrapper. If one reaches mul_unit accidentally, its safe result is 0.
        check_operation("unsupported operation", MULDIV_DIV,
                        32'h1234_5678, 32'h0000_0003);

        check_start_while_busy();
        check_reset_during_operation();

        // Confirm that the unit accepts and completes work after cancellation.
        check_operation("operation after reset", MULDIV_MUL,
                        32'h1234_5678, 32'h0000_0011);

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_a;
            logic [31:0] random_b;
            logic [2:0]  random_op;

            random_a  = $urandom;
            random_b  = $urandom;
            random_op = $urandom_range(MULDIV_MUL, MULDIV_MULHU);

            check_operation(
                $sformatf("random multiplication %0d", i),
                random_op,
                random_a,
                random_b
            );
        end

        if (errors == 0) begin
            $display("PASS: mul_unit_tb (%0d operations)", tests);
        end
        else begin
            $fatal(1, "FAIL: mul_unit_tb had %0d errors across %0d operations",
                   errors, tests);
        end

        $finish;
    end

endmodule
