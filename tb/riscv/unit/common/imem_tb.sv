`timescale 1 ns / 100 ps

module imem_tb #(
    parameter int NUM_RANDOM_TESTS = 1000
);
    import rv32i_pkg::*;

    localparam int WORDS = 16;

    logic [31:0] address;
    logic [31:0] instruction;
    logic access_fault;

    int errors = 0;
    logic address_in_range;
    int range_hits [0:1];
    int offset_hits [0:3];

    imem #(
        .WORDS   (WORDS),
        .HEX_FILE("")
    ) DUT (
        .address    (address),
        .instruction(instruction),
        .access_fault(access_fault)
    );

    task automatic check_read(
        input logic [31:0] test_address,
        input logic [31:0] expected,
        input logic        expected_fault,
        input string       test_name
    );
        address = test_address;
        #1;

        if (instruction !== expected) begin
            $error(
                "%s: address=%h, expected instruction=%h, actual instruction=%h",
                test_name,
                test_address,
                expected,
                instruction
            );
            errors++;
        end

        if (access_fault !== expected_fault) begin
            $error(
                "%s: address=%h, expected fault=%b, actual fault=%b",
                test_name,
                test_address,
                expected_fault,
                access_fault
            );
            errors++;
        end
    endtask

    initial begin
        #1;
        check_read(32'd0, INSTRUCTION_NOP, 1'b0, "default NOP initialization");

        // Initialize memory directly so this unit test does not depend on a
        // simulator working directory or an external file path.
        for (int i = 0; i < WORDS; i++) begin
            DUT.mem[i] = $urandom;
        end

        check_read(32'd0,  DUT.mem[0], 1'b0, "word zero");
        check_read(32'd4,  DUT.mem[1], 1'b0, "word one");
        check_read(32'd8,  DUT.mem[2], 1'b0, "word two");
        check_read(32'd12, DUT.mem[3], 1'b0, "word three");

        check_read(32'd5, INSTRUCTION_NOP, 1'b1, "misaligned instruction address");
        check_read(WORDS * 4, INSTRUCTION_NOP, 1'b1, "first out-of-range address");
        check_read(32'hffff_fffc, INSTRUCTION_NOP, 1'b1, "large out-of-range address");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_address;
            logic [31:0] expected;
            logic expected_fault;

            if ($urandom_range(0, 1)) begin
                random_address = $urandom_range(0, WORDS - 1) * 4;
            end else begin
                if ($urandom_range(0, 1)) begin
                    random_address = ($urandom_range(0, WORDS - 1) * 4) +
                                     $urandom_range(1, 3);
                end else begin
                    random_address = (WORDS * 4) + $urandom_range(0, 1024);
                end
            end

            expected_fault = (random_address[1:0] != 2'b00) ||
                             (random_address[31:2] >= WORDS);
            address_in_range = !expected_fault;
            expected = expected_fault ? INSTRUCTION_NOP :
                                       DUT.mem[random_address[31:2]];
            check_read(
                random_address,
                expected,
                expected_fault,
                $sformatf("random read %0d", i)
            );
            range_hits[!expected_fault]++;
            offset_hits[random_address[1:0]]++;
        end

        for (int i = 0; i <= 1; i++) begin
            if (range_hits[i] == 0) begin
                $error("Missing IMEM in-range coverage value %0d", i);
                errors++;
            end
        end

        for (int i = 0; i < 4; i++) begin
            if (offset_hits[i] == 0) begin
                $error("Missing IMEM byte-offset coverage value %0d", i);
                errors++;
            end
        end

        if (errors == 0) begin
            $display("PASS: imem_tb");
        end else begin
            $fatal(1, "FAIL: imem_tb completed with %0d error(s)", errors);
        end
    end
endmodule
