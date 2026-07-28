`timescale 1ns/1ps

module icache_tb #(
    parameter int NUM_RANDOM_TESTS = 1000
);
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int NUM_SETS   = 4;
    localparam int LINE_WORDS = 4;
    localparam int LINE_BYTES = LINE_WORDS * (DATA_WIDTH / 8);
    localparam int LINE_BITS  = LINE_WORDS * DATA_WIDTH;
    localparam int MEM_WORDS  = 1024;

    localparam int LINE_OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int SET_INDEX_BITS   = $clog2(NUM_SETS);
    localparam int TAG_BITS         = ADDR_WIDTH - SET_INDEX_BITS - LINE_OFFSET_BITS;

    localparam logic [31:0] NOP = 32'h0000_0013;

    logic clk;
    logic rst;

    logic                  cpu_req_valid;
    logic [ADDR_WIDTH-1:0] cpu_req_addr;

    logic                  cpu_resp_valid;
    logic [DATA_WIDTH-1:0] cpu_resp_rdata;
    logic                  cpu_resp_fault;
    logic                  cpu_stall;

    logic                  mem_req_ready;
    logic                  mem_req_valid;
    logic [ADDR_WIDTH-1:0] mem_req_addr;

    logic                  mem_resp_valid;
    logic [LINE_BITS-1:0]  mem_resp_rdata;
    logic                  mem_resp_fault;
    logic                  mem_resp_ready;

    logic [DATA_WIDTH-1:0] backing_memory [0:MEM_WORDS-1];

    logic                  memory_accept_enable;
    logic                  pending_read;
    logic [ADDR_WIDTH-1:0] pending_read_addr;
    int                    response_delay;

    int memory_read_requests;
    int errors;
    int tests;

    // Mirror of the direct-mapped tag state, used to predict hit/miss for
    // the random fetch stream.
    logic                model_valid [0:NUM_SETS-1];
    logic [TAG_BITS-1:0] model_tag   [0:NUM_SETS-1];

    icache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS  (NUM_SETS),
        .LINE_WORDS(LINE_WORDS)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_fault (cpu_resp_fault),
        .cpu_stall      (cpu_stall),
        .mem_req_ready  (mem_req_ready),
        .mem_req_valid  (mem_req_valid),
        .mem_req_addr   (mem_req_addr),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_rdata (mem_resp_rdata),
        .mem_resp_fault (mem_resp_fault),
        .mem_resp_ready (mem_resp_ready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // The backing memory accepts full-line read requests. A refill response
    // is delayed by zero to three extra cycles to exercise
    // ICACHE_REFILL_WAIT.
    assign mem_req_ready = memory_accept_enable &&
                           !pending_read &&
                           !mem_resp_valid;

    function automatic logic [31:0] initial_word(input int word_index);
        initial_word = 32'h8040_2001 ^
                       (32'(word_index) * 32'h0101_0101);
    endfunction

    function automatic logic [LINE_BITS-1:0] pack_backing_line(
        input logic [ADDR_WIDTH-1:0] line_address
    );
        logic [LINE_BITS-1:0] packed_line;
        int base_word;

        begin
            packed_line = '0;
            base_word   = int'(line_address >> 2);

            for (int word = 0; word < LINE_WORDS; word++)
                packed_line[word * DATA_WIDTH +: DATA_WIDTH] =
                    backing_memory[base_word + word];

            pack_backing_line = packed_line;
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] reference_fetch(
        input logic [ADDR_WIDTH-1:0] address
    );
        reference_fetch = backing_memory[int'(address >> 2)];
    endfunction

    // Predict hit or miss with a mirror of the direct-mapped tag array,
    // then account for the fetch installing the line.
    function automatic logic model_predict_hit(
        input logic [ADDR_WIDTH-1:0] address
    );
        logic [SET_INDEX_BITS-1:0] set_index;
        logic [TAG_BITS-1:0]       tag;

        begin
            set_index = address[LINE_OFFSET_BITS +: SET_INDEX_BITS];
            tag       = address[ADDR_WIDTH-1 -: TAG_BITS];

            model_predict_hit = model_valid[set_index] &&
                                (model_tag[set_index] == tag);
        end
    endfunction

    task automatic model_install(
        input logic [ADDR_WIDTH-1:0] address
    );
        logic [SET_INDEX_BITS-1:0] set_index;

        begin
            set_index = address[LINE_OFFSET_BITS +: SET_INDEX_BITS];

            model_valid[set_index] = 1'b1;
            model_tag[set_index]   = address[ADDR_WIDTH-1 -: TAG_BITS];
        end
    endtask

    task automatic initialize_memory();
        for (int word = 0; word < MEM_WORDS; word++)
            backing_memory[word] = initial_word(word);
    endtask

    // Backing-memory model. Read requests create one delayed full-line
    // response. The instruction cache never writes, so there is no write path.
    always @(posedge clk) begin
        if (rst) begin
            pending_read         <= 1'b0;
            pending_read_addr    <= '0;
            response_delay       <= 0;
        mem_resp_valid       <= 1'b0;
        mem_resp_rdata       <= '0;
        mem_resp_fault       <= 1'b0;
            memory_read_requests <= 0;
        end
        else begin
            if (mem_resp_valid && mem_resp_ready)
                mem_resp_valid <= 1'b0;

            if (mem_req_valid && mem_req_ready) begin
                pending_read         <= 1'b1;
                pending_read_addr    <= mem_req_addr;
                response_delay       <= $urandom_range(0, 3);
                memory_read_requests <= memory_read_requests + 1;
            end

            if (pending_read) begin
                if ((response_delay == 0) && !mem_resp_valid) begin
                    mem_resp_rdata <= pack_backing_line(pending_read_addr);
                    mem_resp_valid <= 1'b1;
                    pending_read   <= 1'b0;
                end
                else if (response_delay > 0)
                    response_delay <= response_delay - 1;
            end
        end
    end

    task automatic reset_environment();
        @(negedge clk);
        rst                  = 1'b1;
        cpu_req_valid        = 1'b0;
        cpu_req_addr         = '0;
        memory_accept_enable = 1'b1;

        initialize_memory();

        for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
            model_valid[set_index] = 1'b0;
            model_tag[set_index]   = '0;
        end

        repeat (2) @(posedge clk);
        #1;
        tests++;

        if ((cpu_stall !== 1'b0) ||
            (cpu_resp_valid !== 1'b0) ||
            (mem_req_valid !== 1'b0) ||
            (mem_resp_ready !== 1'b0)) begin
            $error(
                "reset state incorrect: stall=%b resp_valid=%b mem_req_valid=%b mem_resp_ready=%b",
                cpu_stall,
                cpu_resp_valid,
                mem_req_valid,
                mem_resp_ready
            );
            errors++;
        end

        @(negedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
    endtask

    // Present one PC the way the fetch stage would: drive it, freeze on
    // cpu_stall, and capture the instruction once the stall clears. A hit
    // must complete in the same cycle with no stall at all.
    task automatic fetch(
        input  logic [ADDR_WIDTH-1:0] address,
        output logic [DATA_WIDTH-1:0] instruction,
        output logic                  was_miss,
        output logic                  was_fault
    );
        int timeout;

        begin
            @(negedge clk);
            cpu_req_addr  = address;
            cpu_req_valid = 1'b1;
            #1;

            // A miss must raise cpu_stall in the same cycle so the PC
            // register never advances past the unfetched instruction.
            was_miss = cpu_stall;
            timeout  = 0;

            while (cpu_stall) begin
                if (cpu_resp_valid !== 1'b0) begin
                    $error("cpu_resp_valid asserted while cpu_stall high");
                    errors++;
                end

                @(posedge clk);
                #1;
                timeout++;

                if (timeout > 200)
                    $fatal(1,
                           "Timeout waiting for icache stall to clear at address %08h",
                           address);
            end

            if (cpu_resp_valid !== 1'b1) begin
                $error("No fetch response at address %08h", address);
                errors++;
            end

            instruction = cpu_resp_rdata;
            was_fault   = cpu_resp_fault;
        end
    endtask

    task automatic check_fetch(
        input string                 test_name,
        input logic [ADDR_WIDTH-1:0] address,
        input logic                  expected_miss
    );
        logic [DATA_WIDTH-1:0] actual_instruction;
        logic actual_miss;
        logic actual_fault;

        begin
            fetch(address, actual_instruction, actual_miss, actual_fault);

            tests++;

            if ((actual_instruction !== reference_fetch(address)) ||
                (actual_miss !== expected_miss) ||
                (actual_fault !== 1'b0)) begin
                $error(
                    "%s: addr=%08h data=%08h/%08h miss=%b/%b fault=%b/0",
                    test_name,
                    address,
                    actual_instruction,
                    reference_fetch(address),
                    actual_miss,
                    expected_miss,
                    actual_fault
                );
                errors++;
            end
        end
    endtask

    // The stall must drop and the response must appear without any clock
    // edge when the requested word is already cached (zero-cycle hit).
    task automatic check_same_cycle_hit(
        input string                 test_name,
        input logic [ADDR_WIDTH-1:0] address
    );
        begin
            @(negedge clk);
            cpu_req_addr  = address;
            cpu_req_valid = 1'b1;
            #1;

            tests++;

            if ((cpu_stall !== 1'b0) ||
                (cpu_resp_valid !== 1'b1) ||
                (cpu_resp_rdata !== reference_fetch(address)) ||
                (cpu_resp_fault !== 1'b0)) begin
                $error(
                    "%s: addr=%08h stall=%b resp_valid=%b data=%08h/%08h",
                    test_name,
                    address,
                    cpu_stall,
                    cpu_resp_valid,
                    cpu_resp_rdata,
                    reference_fetch(address)
                );
                errors++;
            end
        end
    endtask

    task automatic check_idle_request();
        int read_requests_before;

        begin
            read_requests_before = memory_read_requests;

            // An uncached address without cpu_req_valid must not stall the
            // pipe or generate memory traffic.
            @(negedge clk);
            cpu_req_addr  = 32'h0000_0f00;
            cpu_req_valid = 1'b0;
            #1;

            tests++;

            if ((cpu_stall !== 1'b0) || (cpu_resp_valid !== 1'b0)) begin
                $error("Cache responded to an invalid fetch request");
                errors++;
            end

            repeat (3) begin
                @(posedge clk);
                #1;

                if (mem_req_valid !== 1'b0) begin
                    $error("Invalid fetch request reached backing memory");
                    errors++;
                end
            end

            if (memory_read_requests !== read_requests_before) begin
                $error("Invalid fetch request triggered a refill");
                errors++;
            end
        end
    endtask

    task automatic check_misaligned_fetch();
        int read_requests_before;

        begin
            read_requests_before = memory_read_requests;

            @(negedge clk);
            cpu_req_addr  = 32'h0000_0102;
            cpu_req_valid = 1'b1;
            #1;

            tests++;

            if ((cpu_stall !== 1'b0) ||
                (cpu_resp_valid !== 1'b1) ||
                (cpu_resp_fault !== 1'b1) ||
                (cpu_resp_rdata !== NOP)) begin
                $error(
                    "Misaligned fetch: stall=%b resp_valid=%b fault=%b data=%08h",
                    cpu_stall,
                    cpu_resp_valid,
                    cpu_resp_fault,
                    cpu_resp_rdata
                );
                errors++;
            end

            repeat (3) begin
                @(posedge clk);
                #1;
            end

            if (memory_read_requests !== read_requests_before) begin
                $error("Misaligned fetch reached backing memory");
                errors++;
            end

            @(negedge clk);
            cpu_req_valid = 1'b0;
        end
    endtask

    task automatic check_memory_backpressure();
        logic [ADDR_WIDTH-1:0] held_address;
        int timeout;

        begin
            memory_accept_enable = 1'b0;

            @(negedge clk);
            cpu_req_addr  = 32'h0000_03c0;
            cpu_req_valid = 1'b1;
            #1;

            tests++;

            if (cpu_stall !== 1'b1) begin
                $error("Miss did not stall while memory was backpressured");
                errors++;
            end

            timeout = 0;
            while (!mem_req_valid) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 100)
                    $fatal(1, "Timeout waiting for stalled refill request");
            end

            held_address = mem_req_addr;

            if (held_address !== 32'h0000_03c0) begin
                $error("Refill request address %08h != line base 000003c0",
                       held_address);
                errors++;
            end

            repeat (3) begin
                @(posedge clk);
                #1;

                if ((mem_req_valid !== 1'b1) ||
                    (mem_req_addr !== held_address) ||
                    (cpu_stall !== 1'b1)) begin
                    $error("Refill request changed while backpressured");
                    errors++;
                end
            end

            @(negedge clk);
            memory_accept_enable = 1'b1;

            timeout = 0;
            while (cpu_stall) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 300)
                    $fatal(1, "Timeout after releasing memory backpressure");
            end

            if ((cpu_resp_valid !== 1'b1) ||
                (cpu_resp_rdata !== reference_fetch(32'h0000_03c0))) begin
                $error("Incorrect fetch after memory backpressure");
                errors++;
            end

            model_install(32'h0000_03c0);

            @(negedge clk);
            cpu_req_valid = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        tests  = 0;

        rst                  = 1'b0;
        cpu_req_valid        = 1'b0;
        cpu_req_addr         = '0;
        memory_accept_enable = 1'b1;

        // Cold miss, then hits to every other word of the refilled line.
        reset_environment();

        check_fetch("cold miss",           32'h0000_0100, 1'b1);
        check_fetch("same-address hit",    32'h0000_0100, 1'b0);
        check_fetch("same-line hit +4",    32'h0000_0104, 1'b0);
        check_fetch("same-line hit +8",    32'h0000_0108, 1'b0);
        check_fetch("same-line hit +12",   32'h0000_010c, 1'b0);

        tests++;
        if (memory_read_requests !== 1) begin
            $error("Line refilled more than once: reads=%0d",
                   memory_read_requests);
            errors++;
        end

        // Addresses separated by NUM_SETS * LINE_BYTES map to the same set,
        // so the second address evicts the first (direct mapped: no ways).
        reset_environment();

        check_fetch("conflict fill A",       32'h0000_0040, 1'b1);
        check_fetch("conflict A hit",        32'h0000_0040, 1'b0);
        check_fetch("conflict B evicts A",   32'h0000_0080, 1'b1);
        check_fetch("conflict B hit",        32'h0000_0080, 1'b0);
        check_fetch("conflict A misses again", 32'h0000_0040, 1'b1);
        check_fetch("conflict A hit again",  32'h0000_0040, 1'b0);

        // Sequential fetch streaming: exactly one miss at each line
        // boundary and hits everywhere else, like straight-line code.
        reset_environment();

        for (int address = 32'h0000_0200;
             address < 32'h0000_0200 + (4 * LINE_BYTES);
             address += 4) begin
            check_fetch(
                "sequential stream",
                address,
                (address % LINE_BYTES) == 0
            );
        end

        tests++;
        if (memory_read_requests !== 4) begin
            $error("Sequential stream refilled %0d lines instead of 4",
                   memory_read_requests);
            errors++;
        end

        // Stall behavior: a hit must complete with no clock edge, and a
        // miss must raise cpu_stall in the very same cycle (checked inside
        // the fetch task) so PC and IF/ID freeze in time.
        reset_environment();

        check_fetch("warm line for stall test", 32'h0000_0300, 1'b1);
        check_same_cycle_hit("zero-cycle hit",  32'h0000_0304);
        check_same_cycle_hit("zero-cycle hit repeat", 32'h0000_0308);

        check_idle_request();
        check_misaligned_fetch();

        reset_environment();
        check_memory_backpressure();

        // Random word-aligned fetches are compared against backing memory
        // and against a mirror of the direct-mapped tag state, which
        // predicts every hit and conflict miss.
        reset_environment();

        for (int test_index = 0;
             test_index < NUM_RANDOM_TESTS;
             test_index++) begin
            logic [31:0] address;
            logic [31:0] actual_instruction;
            logic expected_hit;
            logic actual_miss;
            logic actual_fault;

            address      = 32'($urandom_range(0, MEM_WORDS - 1)) << 2;
            expected_hit = model_predict_hit(address);

            fetch(address, actual_instruction, actual_miss, actual_fault);
            model_install(address);

            tests++;

            if ((actual_instruction !== reference_fetch(address)) ||
                (actual_miss !== !expected_hit) ||
                (actual_fault !== 1'b0)) begin
                $error(
                    "Random fetch %0d: addr=%08h data=%08h/%08h miss=%b/%b fault=%b",
                    test_index,
                    address,
                    actual_instruction,
                    reference_fetch(address),
                    actual_miss,
                    !expected_hit,
                    actual_fault
                );
                errors++;
            end
        end

        if (errors == 0)
            $display(
                "PASS: icache_tb (%0d checks, %0d random fetches)",
                tests,
                NUM_RANDOM_TESTS
            );
        else
            $fatal(1,
                   "FAIL: icache_tb had %0d errors across %0d checks",
                   errors,
                   tests);

        $finish;
    end

endmodule
