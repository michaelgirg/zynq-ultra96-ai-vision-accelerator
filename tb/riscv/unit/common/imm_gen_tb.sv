`timescale 1 ns / 100 ps

module imm_gen_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    import rv32i_pkg::*;

    logic [31:0] instruction;
    logic [2:0]  imm_sel;
    logic [31:0] immediate;

    int errors = 0;
    int selector_hits [0:7];
    int sign_hits [0:4][0:1];

    imm_gen DUT (
        .instruction(instruction),
        .imm_sel   (imm_sel),
        .immediate (immediate)
    );

    function automatic logic [31:0] encode_i(input logic signed [11:0] imm);
        return {imm, 5'd1, 3'b000, 5'd2, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_s(input logic signed [11:0] imm);
        return {imm[11:5], 5'd2, 5'd1, 3'b010, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] encode_b(input logic signed [12:0] imm);
        return {
            imm[12],
            imm[10:5],
            5'd2,
            5'd1,
            3'b000,
            imm[4:1],
            imm[11],
            7'b1100011
        };
    endfunction

    function automatic logic [31:0] encode_u(input logic [19:0] imm);
        return {imm, 5'd2, 7'b0110111};
    endfunction

    function automatic logic [31:0] encode_j(input logic signed [20:0] imm);
        return {
            imm[20],
            imm[10:1],
            imm[11],
            imm[19:12],
            5'd2,
            7'b1101111
        };
    endfunction

    function automatic logic [31:0] model_immediate(
        input logic [31:0] test_instruction,
        input logic [2:0]  test_sel
    );
        case (test_sel)
            IMM_I: return {{20{test_instruction[31]}}, test_instruction[31:20]};
            IMM_S: return {
                {20{test_instruction[31]}},
                test_instruction[31:25],
                test_instruction[11:7]
            };
            IMM_B: return {
                {19{test_instruction[31]}},
                test_instruction[31],
                test_instruction[7],
                test_instruction[30:25],
                test_instruction[11:8],
                1'b0
            };
            IMM_U: return {test_instruction[31:12], 12'b0};
            IMM_J: return {
                {11{test_instruction[31]}},
                test_instruction[31],
                test_instruction[19:12],
                test_instruction[20],
                test_instruction[30:21],
                1'b0
            };
            default: return 32'b0;
        endcase
    endfunction

    task automatic check_immediate(
        input logic [2:0]  test_sel,
        input logic [31:0] test_instruction,
        input logic [31:0] expected,
        input string       test_name
    );
        imm_sel     = test_sel;
        instruction = test_instruction;
        #1;
        selector_hits[test_sel]++;
        if (test_sel <= IMM_J) begin
            sign_hits[test_sel][immediate[31]]++;
        end

        if (immediate !== expected) begin
            $error(
                "%s: expected immediate=%h, actual immediate=%h",
                test_name,
                expected,
                immediate
            );
            errors++;
        end
    endtask

    initial begin
        check_immediate(IMM_I, encode_i(12'sd127),  32'd127,       "positive I immediate");
        check_immediate(IMM_I, encode_i(-12'sd1),  32'hffff_ffff, "negative I immediate");
        check_immediate(IMM_S, encode_s(12'sd100), 32'd100,       "positive S immediate");
        check_immediate(IMM_S, encode_s(-12'sd16), 32'hffff_fff0, "negative S immediate");
        check_immediate(IMM_B, encode_b(13'sd16),  32'd16,        "forward B immediate");
        check_immediate(IMM_B, encode_b(-13'sd8),  32'hffff_fff8, "backward B immediate");
        check_immediate(IMM_U, encode_u(20'habcde), 32'habcde000, "U immediate");
        check_immediate(IMM_J, encode_j(21'sd2048), 32'd2048,     "forward J immediate");
        check_immediate(IMM_J, encode_j(-21'sd4),   32'hffff_fffc, "backward J immediate");
        check_immediate(3'b111, 32'hffff_ffff,       32'b0,         "invalid selector");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_instruction;
            logic [2:0] random_sel;

            random_instruction = $urandom;
            random_sel = $urandom_range(0, 7);

            check_immediate(
                random_sel,
                random_instruction,
                model_immediate(random_instruction, random_sel),
                $sformatf("random immediate %0d", i)
            );
        end

        for (int sel = 0; sel < 8; sel++) begin
            if (selector_hits[sel] == 0) begin
                $error("Missing immediate selector coverage value %0d", sel);
                errors++;
            end
        end

        for (int sel = IMM_I; sel <= IMM_J; sel++) begin
            for (int sign_value = 0; sign_value <= 1; sign_value++) begin
                if (sign_hits[sel][sign_value] == 0) begin
                    $error(
                        "Missing immediate coverage selector=%0d sign=%0d",
                        sel,
                        sign_value
                    );
                    errors++;
                end
            end
        end

        if (errors == 0) begin
            $display("PASS: imm_gen_tb");
        end else begin
            $fatal(1, "FAIL: imm_gen_tb completed with %0d error(s)", errors);
        end
    end
endmodule
