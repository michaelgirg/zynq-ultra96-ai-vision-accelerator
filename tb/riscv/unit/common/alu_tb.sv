`timescale 1 ns / 100 ps

module alu_tb #(
    parameter int NUM_RANDOM_TESTS = 5000
);
    import rv32i_pkg::*;

    logic [31:0] op_a;
    logic [31:0] op_b;
    logic [3:0]  alu_op;
    logic [31:0] result;
    logic        zero;

    int errors = 0;
    int operation_hits [0:10];

    alu DUT (.*);

    function automatic logic [31:0] model_alu(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [3:0]  test_op
    );
        logic [31:0] expected;
        expected = '0;

        case (test_op)
            ALU_ADD:    expected = test_a + test_b;
            ALU_SUB:    expected = test_a - test_b;
            ALU_SLL:    expected = test_a << test_b[4:0];
            ALU_SRL:    expected = test_a >> test_b[4:0];
            ALU_SRA:    expected = $signed(test_a) >>> test_b[4:0];
            ALU_AND:    expected = test_a & test_b;
            ALU_OR:     expected = test_a | test_b;
            ALU_XOR:    expected = test_a ^ test_b;
            ALU_SLT:    expected[0] = $signed(test_a) < $signed(test_b);
            ALU_SLTU:   expected[0] = test_a < test_b;
            ALU_COPY_B: expected = test_b;
            default:    expected = '0;
        endcase

        return expected;
    endfunction

    task automatic check_alu(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [3:0]  test_op,
        input string       test_name
    );
        logic [31:0] expected;

        op_a = test_a;
        op_b = test_b;
        alu_op = test_op;
        expected = model_alu(test_a, test_b, test_op);
        #1;

        if (test_op <= ALU_COPY_B) begin
            operation_hits[test_op]++;
        end

        if (result !== expected) begin
            $error(
                "%s: op=%0d a=%h b=%h expected=%h actual=%h",
                test_name,
                test_op,
                test_a,
                test_b,
                expected,
                result
            );
            errors++;
        end

        if (zero !== (expected == 32'b0)) begin
            $error("%s: zero flag mismatch", test_name);
            errors++;
        end
    endtask

    initial begin
        check_alu(32'd7, 32'd5, ALU_ADD, "ADD");
        check_alu(32'd7, 32'd5, ALU_SUB, "SUB");
        check_alu(32'h0000_0001, 32'd31, ALU_SLL, "SLL");
        check_alu(32'h8000_0000, 32'd31, ALU_SRL, "SRL");
        check_alu(32'h8000_0000, 32'd4, ALU_SRA, "SRA");
        check_alu(32'hf0f0_0f0f, 32'h0ff0_ff00, ALU_AND, "AND");
        check_alu(32'hf0f0_0f0f, 32'h0ff0_ff00, ALU_OR, "OR");
        check_alu(32'hf0f0_0f0f, 32'h0ff0_ff00, ALU_XOR, "XOR");
        check_alu(32'hffff_ffff, 32'd1, ALU_SLT, "signed SLT");
        check_alu(32'hffff_ffff, 32'd1, ALU_SLTU, "unsigned SLTU");
        check_alu(32'hdead_beef, 32'h1234_5678, ALU_COPY_B, "COPY_B");
        check_alu(32'd5, 32'd5, ALU_SUB, "zero result");
        check_alu(32'hffff_ffff, 32'hffff_ffff, 4'hf, "invalid operation");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [3:0] random_op;
            random_op = $urandom_range(ALU_ADD, ALU_COPY_B);
            check_alu(
                $urandom,
                $urandom,
                random_op,
                $sformatf("random ALU test %0d", i)
            );
        end

        for (int op = ALU_ADD; op <= ALU_COPY_B; op++) begin
            if (operation_hits[op] == 0) begin
                $error("Missing ALU operation coverage for operation %0d", op);
                errors++;
            end
        end

        if (errors == 0) begin
            $display("PASS: alu_tb");
        end else begin
            $fatal(1, "FAIL: alu_tb completed with %0d error(s)", errors);
        end
    end
endmodule
