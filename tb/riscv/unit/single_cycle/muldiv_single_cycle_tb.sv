`timescale 1ns/1ps

module muldiv_single_cycle_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    import rv32i_pkg::*;

    muldiv_op_t op;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;

    int errors;
    int tests;

    muldiv_single_cycle dut (
        .op       (op),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result   (result)
    );

    function automatic logic [31:0] reference_result(
        input muldiv_op_t test_op,
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

        signed_product = signed_a_extended * signed_b_extended;
        signed_unsigned_product = signed_a_extended * unsigned_b_extended;
        unsigned_product = unsigned_a_extended * unsigned_b_extended;

        reference_result = '0;

        case (test_op)
            MULDIV_MUL:    reference_result = unsigned_product[31:0];
            MULDIV_MULH:   reference_result = signed_product[63:32];
            MULDIV_MULHSU: reference_result = signed_unsigned_product[63:32];
            MULDIV_MULHU:  reference_result = unsigned_product[63:32];

            MULDIV_DIV: begin
                if (test_b == 32'b0) reference_result = 32'hffff_ffff;
                else if ((test_a == 32'h8000_0000) &&
                         (test_b == 32'hffff_ffff)) reference_result = 32'h8000_0000;
                else reference_result = $signed(test_a) / $signed(test_b);
            end

            MULDIV_DIVU: begin
                if (test_b == 32'b0) reference_result = 32'hffff_ffff;
                else reference_result = $unsigned(test_a) / $unsigned(test_b);
            end

            MULDIV_REM: begin
                if (test_b == 32'b0) reference_result = test_a;
                else if ((test_a == 32'h8000_0000) &&
                         (test_b == 32'hffff_ffff)) reference_result = 32'b0;
                else reference_result = $signed(test_a) % $signed(test_b);
            end

            MULDIV_REMU: begin
                if (test_b == 32'b0) reference_result = test_a;
                else reference_result = $unsigned(test_a) % $unsigned(test_b);
            end

            default: reference_result = '0;
        endcase
    endfunction

    task automatic check_operation(
        input string test_name,
        input muldiv_op_t test_op,
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] expected
    );
        op        = test_op;
        operand_a = test_a;
        operand_b = test_b;
        #1;
        tests++;

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
    endtask

    initial begin
        errors = 0;
        tests  = 0;
        op = MULDIV_MUL;
        operand_a = '0;
        operand_b = '0;

        // Multiplication directed cases cover zero, positive, negative,
        // mixed-signedness, and values whose upper product bits matter.
        check_operation("MUL zero", MULDIV_MUL,
                        32'h0000_0000, 32'hffff_ffff, 32'h0000_0000);
        check_operation("MUL positive", MULDIV_MUL,
                        32'd7, 32'd9, 32'd63);
        check_operation("MUL negative", MULDIV_MUL,
                        32'hffff_fffe, 32'd3, 32'hffff_fffa);
        check_operation("MUL low overflow", MULDIV_MUL,
                        32'h8000_0000, 32'd2, 32'h0000_0000);

        check_operation("MULH negative", MULDIV_MULH,
                        32'hffff_fffe, 32'd3, 32'hffff_ffff);
        check_operation("MULH minimum", MULDIV_MULH,
                        32'h8000_0000, 32'd2, 32'hffff_ffff);
        check_operation("MULH positive maximum", MULDIV_MULH,
                        32'h7fff_ffff, 32'h7fff_ffff, 32'h3fff_ffff);

        check_operation("MULHSU negative times unsigned maximum", MULDIV_MULHSU,
                        32'hffff_fffe, 32'hffff_ffff, 32'hffff_fffe);
        check_operation("MULHSU positive times unsigned maximum", MULDIV_MULHSU,
                        32'h7fff_ffff, 32'hffff_ffff, 32'h7fff_fffe);

        check_operation("MULHU maximum", MULDIV_MULHU,
                        32'hffff_ffff, 32'hffff_ffff, 32'hffff_fffe);
        check_operation("MULHU high bit", MULDIV_MULHU,
                        32'h8000_0000, 32'd2, 32'h0000_0001);

        // Signed division and remainder must truncate toward zero and keep
        // the remainder's sign equal to the dividend's sign.
        check_operation("DIV positive", MULDIV_DIV,
                        32'd7, 32'd3, 32'd2);
        check_operation("DIV negative dividend", MULDIV_DIV,
                        32'hffff_fff9, 32'd3, 32'hffff_fffe);
        check_operation("DIV negative divisor", MULDIV_DIV,
                        32'd7, 32'hffff_fffd, 32'hffff_fffe);
        check_operation("DIV both negative", MULDIV_DIV,
                        32'hffff_fff9, 32'hffff_fffd, 32'd2);
        check_operation("DIV by zero", MULDIV_DIV,
                        32'h1234_5678, 32'b0, 32'hffff_ffff);
        check_operation("DIV signed overflow", MULDIV_DIV,
                        32'h8000_0000, 32'hffff_ffff, 32'h8000_0000);

        check_operation("DIVU", MULDIV_DIVU,
                        32'hffff_ffff, 32'd3, 32'h5555_5555);
        check_operation("DIVU by zero", MULDIV_DIVU,
                        32'h1234_5678, 32'b0, 32'hffff_ffff);

        check_operation("REM positive", MULDIV_REM,
                        32'd7, 32'd3, 32'd1);
        check_operation("REM negative dividend", MULDIV_REM,
                        32'hffff_fff9, 32'd3, 32'hffff_ffff);
        check_operation("REM negative divisor", MULDIV_REM,
                        32'd7, 32'hffff_fffd, 32'd1);
        check_operation("REM both negative", MULDIV_REM,
                        32'hffff_fff9, 32'hffff_fffd, 32'hffff_ffff);
        check_operation("REM by zero", MULDIV_REM,
                        32'h1234_5678, 32'b0, 32'h1234_5678);
        check_operation("REM signed overflow", MULDIV_REM,
                        32'h8000_0000, 32'hffff_ffff, 32'b0);

        check_operation("REMU", MULDIV_REMU,
                        32'hffff_ffff, 32'd3, 32'b0);
        check_operation("REMU by zero", MULDIV_REMU,
                        32'h89ab_cdef, 32'b0, 32'h89ab_cdef);

        // Random stimulus checks every operation against the reference model.
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_a;
            logic [31:0] random_b;
            muldiv_op_t random_op;

            random_a = $urandom;
            random_b = $urandom;
            random_op = muldiv_op_t'($urandom_range(0, 7));

            check_operation(
                $sformatf("random operation %0d", i),
                random_op,
                random_a,
                random_b,
                reference_result(random_op, random_a, random_b)
            );
        end

        if (errors == 0) begin
            $display("PASS: muldiv_single_cycle_tb (%0d tests)", tests);
        end else begin
            $fatal(1, "FAIL: muldiv_single_cycle_tb had %0d errors", errors);
        end

        $finish;
    end

endmodule
