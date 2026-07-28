`timescale 1 ns / 100 ps

module pc_tb #(
    parameter int NUM_RANDOM_TESTS = 1000
);
    localparam logic [31:0] RST_PC = 32'h0000_0100;

    logic        clk = 1'b0;
    logic        rst;
    logic        en;
    logic [31:0] next_pc;
    logic [31:0] pc;

    int errors = 0;
    logic [31:0] expected_pc;
    int control_hits [0:1][0:1];

    pc #(
        .RST_PC(RST_PC)
    ) DUT (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .next_pc(next_pc),
        .pc     (pc)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    task automatic check_pc(
        input logic [31:0] expected,
        input string       test_name
    );
        if (pc !== expected) begin
            $error("%s: expected pc=%h, actual pc=%h", test_name, expected, pc);
            errors++;
        end
    endtask

    initial begin : provide_stimulus
        rst     <= 1'b1;
        en      <= 1'b0;
        next_pc <= '0;
        expected_pc = RST_PC;

        repeat (2) @(posedge clk);
        @(negedge clk);
        check_pc(RST_PC, "synchronous reset");

        rst     <= 1'b0;
        en      <= 1'b1;
        next_pc <= 32'h0000_0104;
        @(posedge clk);
        @(negedge clk);
        check_pc(32'h0000_0104, "enabled update");

        en      <= 1'b0;
        next_pc <= 32'hdead_beef;
        @(posedge clk);
        @(negedge clk);
        check_pc(32'h0000_0104, "disabled hold");

        en      <= 1'b1;
        next_pc <= 32'h0000_0200;
        @(posedge clk);
        @(negedge clk);
        check_pc(32'h0000_0200, "second enabled update");

        rst     <= 1'b1;
        en      <= 1'b1;
        next_pc <= 32'hffff_ffff;
        @(posedge clk);
        @(negedge clk);
        check_pc(RST_PC, "reset priority");

        // Randomly exercise reset, enable, and hold behavior. Inputs change on
        // the falling edge so they are stable before the active clock edge.
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            rst     <= ($urandom_range(0, 15) == 0);
            en      <= $urandom_range(0, 1);
            next_pc <= $urandom;
            @(posedge clk);

            if (rst) begin
                expected_pc = RST_PC;
            end else if (en) begin
                expected_pc = next_pc;
            end

            @(negedge clk);
            control_hits[rst][en]++;
            check_pc(expected_pc, $sformatf("random test %0d", i));
        end

        for (int rst_value = 0; rst_value <= 1; rst_value++) begin
            for (int en_value = 0; en_value <= 1; en_value++) begin
                if (control_hits[rst_value][en_value] == 0) begin
                    $error("Missing PC control case rst=%0d en=%0d", rst_value, en_value);
                    errors++;
                end
            end
        end

        if (errors == 0) begin
            $display("PASS: pc_tb");
        end else begin
            $fatal(1, "FAIL: pc_tb completed with %0d error(s)", errors);
        end

        disable generate_clock;
    end
endmodule
