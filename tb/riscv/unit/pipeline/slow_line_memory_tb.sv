`timescale 1ns/1ps

module slow_line_memory_tb;
    localparam int DATA_WIDTH  = 32;
    localparam int LINE_WORDS  = 4;
    localparam int LINE_BITS   = DATA_WIDTH * LINE_WORDS;
    localparam int DEPTH_WORDS = 64;
    localparam int LATENCY     = 3;

    logic clk;
    logic rst;
    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [31:0] req_addr;
    logic [LINE_BITS-1:0] req_wdata;
    logic resp_valid;
    logic resp_ready;
    logic [LINE_BITS-1:0] resp_rdata;
    logic resp_fault;

    int errors;
    int tests;

    slow_line_memory #(
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .DEPTH_WORDS(DEPTH_WORDS),
        .LATENCY    (LATENCY)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_write (req_write),
        .req_addr  (req_addr),
        .req_wdata (req_wdata),
        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_rdata(resp_rdata),
        .resp_fault(resp_fault)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic send_request(
        input logic write_request,
        input logic [31:0] address,
        input logic [LINE_BITS-1:0] write_line
    );
        @(negedge clk);
        req_valid = 1'b1;
        req_write = write_request;
        req_addr  = address;
        req_wdata = write_line;

        while (!req_ready) @(negedge clk);
        @(posedge clk);
        #1;

        req_valid = 1'b0;
    endtask

    task automatic wait_for_read_response(
        input logic [LINE_BITS-1:0] expected_line,
        input logic expected_fault
    );
        for (int cycle = 1; cycle < LATENCY; cycle++) begin
            @(posedge clk);
            #1;
            tests++;
            if (resp_valid !== 1'b0) begin
                $error("Read response arrived before latency expired");
                errors++;
            end
        end

        @(posedge clk);
        #1;
        tests++;

        if ((resp_valid !== 1'b1) ||
            (resp_rdata !== expected_line) ||
            (resp_fault !== expected_fault)) begin
            $error("Read response mismatch: valid=%b data=%h/%h fault=%b/%b",
                   resp_valid, resp_rdata, expected_line,
                   resp_fault, expected_fault);
            errors++;
        end
    endtask

    initial begin
        logic [LINE_BITS-1:0] expected_line;
        logic [LINE_BITS-1:0] replacement_line;

        errors = 0;
        tests  = 0;

        rst        = 1'b1;
        req_valid  = 1'b0;
        req_write  = 1'b0;
        req_addr   = '0;
        req_wdata  = '0;
        resp_ready = 1'b0;

        for (int line = 0; line < (DEPTH_WORDS / LINE_WORDS); line++) begin
            for (int word = 0; word < LINE_WORDS; word++) begin
                dut.mem[line][word * DATA_WIDTH +: DATA_WIDTH] =
                    32'h1000_0000 + (line * LINE_WORDS) + word;
            end
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        expected_line = {
            32'h1000_0007,
            32'h1000_0006,
            32'h1000_0005,
            32'h1000_0004
        };

        // Read address 0x10, verify exact delay and stable backpressure.
        send_request(1'b0, 32'h0000_0010, '0);
        wait_for_read_response(expected_line, 1'b0);

        repeat (3) begin
            @(posedge clk);
            #1;
            tests++;
            if ((resp_valid !== 1'b1) ||
                (resp_rdata !== expected_line) ||
                (req_ready !== 1'b0)) begin
                $error("Response changed while consumer applied backpressure");
                errors++;
            end
        end

        @(negedge clk);
        resp_ready = 1'b1;
        @(posedge clk);
        #1;
        resp_ready = 1'b0;

        tests++;
        if ((resp_valid !== 1'b0) || (req_ready !== 1'b1)) begin
            $error("Memory did not return to idle after response handshake");
            errors++;
        end

        // A complete-line write consumes the configured latency, produces no
        // response, and is visible to a later read.
        replacement_line = {
            32'hd3d3_d3d3,
            32'hc2c2_c2c2,
            32'hb1b1_b1b1,
            32'ha0a0_a0a0
        };

        send_request(1'b1, 32'h0000_0020, replacement_line);
        repeat (LATENCY - 1) begin
            @(posedge clk);
            #1;
            tests++;
            if (req_ready !== 1'b0) begin
                $error("Write completed before latency expired");
                errors++;
            end
        end

        @(posedge clk);
        #1;
        tests++;
        if ((req_ready !== 1'b1) || (resp_valid !== 1'b0)) begin
            $error("Write did not complete without a response");
            errors++;
        end

        send_request(1'b0, 32'h0000_0020, '0);
        wait_for_read_response(replacement_line, 1'b0);
        @(negedge clk);
        resp_ready = 1'b1;
        @(posedge clk);
        #1;
        resp_ready = 1'b0;

        // Misaligned and out-of-range lines return delayed fault responses and
        // never index outside the backing array.
        send_request(1'b0, 32'h0000_0024, '0);
        wait_for_read_response('0, 1'b1);
        @(negedge clk);
        resp_ready = 1'b1;
        @(posedge clk);
        #1;
        resp_ready = 1'b0;

        send_request(1'b0, 32'hffff_fff0, '0);
        wait_for_read_response('0, 1'b1);
        @(negedge clk);
        resp_ready = 1'b1;
        @(posedge clk);
        #1;

        if (errors == 0)
            $display("PASS: slow_line_memory_tb (%0d checks)", tests);
        else
            $fatal(1, "FAIL: slow_line_memory_tb had %0d errors", errors);

        $finish;
    end

endmodule
