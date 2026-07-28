`timescale 1 ns / 100 ps

module regfile_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    logic        clk = 1'b0;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;
    logic        we;

    logic [31:0] model [0:31];
    int errors = 0;
    int write_hits [0:1];
    int x0_write_attempts = 0;

    regfile DUT (.*);

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    task automatic check_reads(input string test_name);
        logic [31:0] expected_rs1;
        logic [31:0] expected_rs2;

        expected_rs1 = (rs1_addr == 5'd0) ? 32'b0 : model[rs1_addr];
        expected_rs2 = (rs2_addr == 5'd0) ? 32'b0 : model[rs2_addr];

        if (rs1_data !== expected_rs1) begin
            $error(
                "%s: rs1 x%0d expected=%h actual=%h",
                test_name,
                rs1_addr,
                expected_rs1,
                rs1_data
            );
            errors++;
        end

        if (rs2_data !== expected_rs2) begin
            $error(
                "%s: rs2 x%0d expected=%h actual=%h",
                test_name,
                rs2_addr,
                expected_rs2,
                rs2_data
            );
            errors++;
        end
    endtask

    initial begin : provide_stimulus
        for (int i = 0; i < 32; i++) begin
            model[i] = '0;
        end

        rs1_addr <= '0;
        rs2_addr <= '0;
        rd_addr  <= '0;
        rd_data  <= '0;
        we       <= 1'b0;
        @(negedge clk);
        check_reads("initial x0 reads");

        // Verify explicitly that writes to x0 are ignored.
        rd_addr <= 5'd0;
        rd_data <= 32'hffff_ffff;
        we      <= 1'b1;
        @(posedge clk);
        x0_write_attempts++;
        @(negedge clk);
        rs1_addr <= 5'd0;
        rs2_addr <= 5'd0;
        #1;
        check_reads("explicit x0 write");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic random_we;
            logic [4:0] random_rd_addr;
            logic [31:0] random_rd_data;

            random_we = $urandom_range(0, 1);
            random_rd_addr = $urandom_range(0, 31);
            random_rd_data = $urandom;

            rs1_addr <= $urandom_range(0, 31);
            rs2_addr <= $urandom_range(0, 31);
            rd_addr  <= random_rd_addr;
            rd_data  <= random_rd_data;
            we       <= random_we;

            @(posedge clk);
            write_hits[random_we]++;

            if (random_we && (random_rd_addr != 5'd0)) begin
                model[random_rd_addr] = random_rd_data;
            end else if (random_we) begin
                x0_write_attempts++;
            end

            @(negedge clk);
            check_reads($sformatf("random register-file test %0d", i));

            rs1_addr <= 5'd0;
            rs2_addr <= 5'd0;
            #1;
            check_reads($sformatf("x0 check %0d", i));
        end

        if ((write_hits[0] == 0) || (write_hits[1] == 0)) begin
            $error("Register-file test did not cover both write-enable values");
            errors++;
        end

        if (x0_write_attempts == 0) begin
            $error("Register-file test did not attempt a write to x0");
            errors++;
        end

        if (errors == 0) begin
            $display("PASS: regfile_tb");
        end else begin
            $fatal(1, "FAIL: regfile_tb completed with %0d error(s)", errors);
        end

        disable generate_clock;
    end
endmodule
