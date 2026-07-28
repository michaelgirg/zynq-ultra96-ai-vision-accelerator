`timescale 1 ns / 100 ps

module branch_unit_tb #(
    parameter int NUM_RANDOM_TESTS = 5000
);
    import rv32i_pkg::*;

    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [2:0]  branch_op;
    logic        branch_taken;

    int errors = 0;
    int result_hits [0:7][0:1];

    branch_unit DUT (
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data),
        .branch_op   (branch_op),
        .branch_taken(branch_taken)
    );

    task automatic check_branch(
        input logic [2:0]  test_op,
        input logic [31:0] test_rs1,
        input logic [31:0] test_rs2,
        input logic        expected,
        input string       test_name
    );
        branch_op = test_op;
        rs1_data  = test_rs1;
        rs2_data  = test_rs2;
        #1;
        result_hits[test_op][branch_taken]++;

        if (branch_taken !== expected) begin
            $error(
                "%s: op=%0d rs1=%h rs2=%h expected=%b actual=%b",
                test_name,
                test_op,
                test_rs1,
                test_rs2,
                expected,
                branch_taken
            );
            errors++;
        end
    endtask

    function automatic logic model_branch(
        input logic [2:0]  test_op,
        input logic [31:0] test_rs1,
        input logic [31:0] test_rs2
    );
        case (test_op)
            BR_EQ:   return test_rs1 == test_rs2;
            BR_NE:   return test_rs1 != test_rs2;
            BR_LT:   return $signed(test_rs1) < $signed(test_rs2);
            BR_GE:   return $signed(test_rs1) >= $signed(test_rs2);
            BR_LTU:  return test_rs1 < test_rs2;
            BR_GEU:  return test_rs1 >= test_rs2;
            default: return 1'b0;
        endcase
    endfunction

    initial begin
        check_branch(BR_NONE, 32'd1, 32'd1, 1'b0, "no branch operation");
        check_branch(BR_EQ,   32'd9, 32'd9, 1'b1, "BEQ taken");
        check_branch(BR_EQ,   32'd9, 32'd8, 1'b0, "BEQ not taken");
        check_branch(BR_NE,   32'd9, 32'd8, 1'b1, "BNE taken");
        check_branch(BR_NE,   32'd9, 32'd9, 1'b0, "BNE not taken");

        check_branch(BR_LT, 32'hffff_ffff, 32'd1, 1'b1, "BLT signed negative");
        check_branch(BR_LT, 32'd1, 32'hffff_ffff, 1'b0, "BLT signed positive");
        check_branch(BR_GE, 32'd9, 32'd8, 1'b1, "BGE greater");
        check_branch(BR_GE, 32'd8, 32'd9, 1'b0, "BGE less");

        check_branch(BR_LTU, 32'd9, 32'd8, 1'b0, "BLTU unsigned greater");
        check_branch(BR_LTU, 32'd8, 32'd9, 1'b1, "BLTU unsigned less");
        check_branch(BR_GEU, 32'hffff_ffff, 32'd1, 1'b1, "BGEU unsigned large");
        check_branch(BR_GEU, 32'd1, 32'hffff_ffff, 1'b0, "BGEU unsigned small");
        check_branch(3'b111, 32'd1, 32'd0, 1'b0, "invalid branch operation");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [2:0] random_op;
            logic [31:0] random_rs1;
            logic [31:0] random_rs2;

            random_op  = $urandom_range(0, 7);
            random_rs1 = $urandom;

            // Force equal operands regularly so both outcomes of EQ/NE and
            // boundary behavior of GE/GEU are exercised.
            if ((i % 8) == 0) begin
                random_rs2 = random_rs1;
            end else begin
                random_rs2 = $urandom;
            end

            check_branch(
                random_op,
                random_rs1,
                random_rs2,
                model_branch(random_op, random_rs1, random_rs2),
                $sformatf("random branch %0d", i)
            );
        end

        for (int op = BR_EQ; op <= BR_GEU; op++) begin
            for (int result_value = 0; result_value <= 1; result_value++) begin
                if (result_hits[op][result_value] == 0) begin
                    $error(
                        "Missing branch coverage op=%0d result=%0d",
                        op,
                        result_value
                    );
                    errors++;
                end
            end
        end

        if (result_hits[BR_NONE][0] == 0) begin
            $error("Missing BR_NONE coverage");
            errors++;
        end

        if (result_hits[3'b111][0] == 0) begin
            $error("Missing invalid branch-op coverage");
            errors++;
        end

        if (errors == 0) begin
            $display("PASS: branch_unit_tb");
        end else begin
            $fatal(1, "FAIL: branch_unit_tb completed with %0d error(s)", errors);
        end
    end
endmodule
