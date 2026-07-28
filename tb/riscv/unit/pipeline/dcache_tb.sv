`timescale 1ns/1ps

module dcache_tb #(
    parameter int NUM_RANDOM_TESTS = 1000,
    parameter int NUM_WAYS         = 2
);
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int NUM_SETS   = 4;
    localparam int LINE_WORDS = 4;
    localparam int LINE_BYTES = LINE_WORDS * (DATA_WIDTH / 8);
    localparam int LINE_BITS  = LINE_WORDS * DATA_WIDTH;
    localparam int MEM_WORDS  = 1024;

    logic clk;
    logic rst;

    logic                  cpu_req_valid;
    logic                  cpu_req_write;
    logic [ADDR_WIDTH-1:0] cpu_req_addr;
    logic [DATA_WIDTH-1:0] cpu_req_wdata;
    logic [2:0]            cpu_req_funct3;
    logic                  cpu_req_ready;

    logic                  cpu_resp_ready;
    logic                  cpu_resp_valid;
    logic [DATA_WIDTH-1:0] cpu_resp_rdata;
    logic                  cpu_resp_hit;
    logic                  cpu_resp_miss;
    logic                  cpu_resp_fault;

    logic                  mem_req_ready;
    logic                  mem_req_valid;
    logic                  mem_req_write;
    logic [ADDR_WIDTH-1:0] mem_req_addr;
    logic [LINE_BITS-1:0]  mem_req_wdata;

    logic                  mem_resp_valid;
    logic [LINE_BITS-1:0]  mem_resp_rdata;
    logic                  mem_resp_fault;
    logic                  mem_resp_ready;

    logic [DATA_WIDTH-1:0] backing_memory   [0:MEM_WORDS-1];
    logic [DATA_WIDTH-1:0] reference_memory [0:MEM_WORDS-1];

    logic                  memory_accept_enable;
    logic                  pending_read;
    logic [ADDR_WIDTH-1:0] pending_read_addr;
    int                    response_delay;

    int memory_read_requests;
    int memory_write_requests;
    int errors;
    int tests;

    dcache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS  (NUM_SETS),
        .NUM_WAYS  (NUM_WAYS),
        .LINE_WORDS(LINE_WORDS)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .cpu_req_valid  (cpu_req_valid),
        .cpu_req_write  (cpu_req_write),
        .cpu_req_addr   (cpu_req_addr),
        .cpu_req_wdata  (cpu_req_wdata),
        .cpu_req_funct3 (cpu_req_funct3),
        .cpu_req_ready  (cpu_req_ready),
        .cpu_resp_ready (cpu_resp_ready),
        .cpu_resp_valid (cpu_resp_valid),
        .cpu_resp_rdata (cpu_resp_rdata),
        .cpu_resp_hit   (cpu_resp_hit),
        .cpu_resp_miss  (cpu_resp_miss),
        .cpu_resp_fault (cpu_resp_fault),
        .mem_req_ready  (mem_req_ready),
        .mem_req_valid  (mem_req_valid),
        .mem_req_write  (mem_req_write),
        .mem_req_addr   (mem_req_addr),
        .mem_req_wdata  (mem_req_wdata),
        .mem_resp_valid (mem_resp_valid),
        .mem_resp_rdata (mem_resp_rdata),
        .mem_resp_fault (mem_resp_fault),
        .mem_resp_ready (mem_resp_ready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // The backing memory accepts full-line requests. A refill response is
    // delayed by zero to three extra cycles to exercise CACHE_REFILL_WAIT.
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

    task automatic initialize_memory();
        for (int word = 0; word < MEM_WORDS; word++) begin
            backing_memory[word]   = initial_word(word);
            reference_memory[word] = initial_word(word);
        end
    endtask

    // A separate architectural model is updated on every CPU store. Backing
    // memory is updated only on cache writeback, which lets the test distinguish
    // correct write-back behavior from accidentally writing through.
    task automatic reference_store(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [2:0]            funct3,
        input logic [DATA_WIDTH-1:0] write_data
    );
        logic [DATA_WIDTH-1:0] current_word;
        int word_index;
        int byte_position;

        begin
            word_index    = int'(address >> 2);
            byte_position = int'(address[1:0]) * 8;
            current_word  = reference_memory[word_index];

            case (funct3)
                3'b000:
                    current_word[byte_position +: 8] = write_data[7:0];

                3'b001:
                    current_word[byte_position +: 16] = write_data[15:0];

                3'b010:
                    current_word = write_data;

                default:
                    current_word = current_word;
            endcase

            reference_memory[word_index] = current_word;
        end
    endtask

    function automatic logic [DATA_WIDTH-1:0] reference_load(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [2:0]            funct3
    );
        logic [DATA_WIDTH-1:0] word;
        logic [7:0] selected_byte;
        logic [15:0] selected_half;
        int byte_position;

        begin
            word = reference_memory[int'(address >> 2)];
            byte_position = int'(address[1:0]) * 8;
            selected_byte = word[byte_position +: 8];
            selected_half = address[1] ? word[31:16] : word[15:0];

            case (funct3)
                3'b000: reference_load =
                    {{24{selected_byte[7]}}, selected_byte};
                3'b001: reference_load =
                    {{16{selected_half[15]}}, selected_half};
                3'b010: reference_load = word;
                3'b100: reference_load = {24'b0, selected_byte};
                3'b101: reference_load = {16'b0, selected_half};
                default: reference_load = '0;
            endcase
        end
    endfunction

    // Backing-memory model. Write requests commit a complete dirty line when
    // accepted. Read requests create one delayed full-line response.
    always @(posedge clk) begin
        if (rst) begin
            pending_read         <= 1'b0;
            pending_read_addr    <= '0;
            response_delay       <= 0;
            mem_resp_valid       <= 1'b0;
            mem_resp_rdata       <= '0;
            mem_resp_fault       <= 1'b0;
            memory_read_requests <= 0;
            memory_write_requests <= 0;
        end
        else begin
            if (mem_resp_valid && mem_resp_ready)
                mem_resp_valid <= 1'b0;

            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_write) begin
                    int base_word;

                    base_word = int'(mem_req_addr >> 2);

                    for (int word = 0; word < LINE_WORDS; word++) begin
                        backing_memory[base_word + word] <=
                            mem_req_wdata[word * DATA_WIDTH +: DATA_WIDTH];
                    end

                    memory_write_requests <= memory_write_requests + 1;
                end
                else begin
                    pending_read      <= 1'b1;
                    pending_read_addr <= mem_req_addr;
                    response_delay    <= $urandom_range(0, 3);
                    memory_read_requests <= memory_read_requests + 1;
                end
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
        cpu_req_write        = 1'b0;
        cpu_req_addr         = '0;
        cpu_req_wdata        = '0;
        cpu_req_funct3       = 3'b010;
        cpu_resp_ready       = 1'b1;
        memory_accept_enable = 1'b1;

        initialize_memory();

        repeat (2) @(posedge clk);
        #1;
        tests++;

        if ((cpu_req_ready !== 1'b1) ||
            (cpu_resp_valid !== 1'b0) ||
            (mem_req_valid !== 1'b0) ||
            (mem_resp_ready !== 1'b0)) begin
            $error(
                "reset state incorrect: req_ready=%b resp_valid=%b mem_req_valid=%b mem_resp_ready=%b",
                cpu_req_ready,
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

    task automatic cpu_access(
        input logic                  write_request,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [2:0]            funct3,
        output logic [DATA_WIDTH-1:0] response,
        output logic                 was_hit,
        output logic                 was_miss,
        output logic                 was_fault
    );
        int timeout;

        begin
            cpu_resp_ready = 1'b1;

            @(negedge clk);
            timeout = 0;

            while (!cpu_req_ready) begin
                @(negedge clk);
                timeout++;

                if (timeout > 200)
                    $fatal(1, "Timeout waiting for cpu_req_ready");
            end

            cpu_req_write  = write_request;
            cpu_req_addr   = address;
            cpu_req_wdata  = write_data;
            cpu_req_funct3 = funct3;
            cpu_req_valid  = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            cpu_req_valid = 1'b0;

            timeout = 0;

            while (!cpu_resp_valid) begin
                @(posedge clk);
                #1;
                timeout++;

                if (timeout > 300)
                    $fatal(1,
                           "Timeout waiting for cache response at address %08h",
                           address);
            end

            response  = cpu_resp_rdata;
            was_hit   = cpu_resp_hit;
            was_miss  = cpu_resp_miss;
            was_fault = cpu_resp_fault;

            // The cache consumes the response on the next rising edge because
            // cpu_resp_ready remains asserted.
            @(posedge clk);
            #1;

            if (cpu_resp_valid !== 1'b0) begin
                $error("Response valid did not clear after handshake");
                errors++;
            end
        end
    endtask

    task automatic check_access(
        input string test_name,
        input logic                  write_request,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] write_data,
        input logic [2:0]            funct3,
        input logic [DATA_WIDTH-1:0] expected_data,
        input logic                  expected_hit,
        input logic                  expected_miss,
        input logic                  expected_fault
    );
        logic [DATA_WIDTH-1:0] actual_data;
        logic actual_hit;
        logic actual_miss;
        logic actual_fault;

        begin
            cpu_access(
                write_request,
                address,
                write_data,
                funct3,
                actual_data,
                actual_hit,
                actual_miss,
                actual_fault
            );

            tests++;

            if ((actual_data !== expected_data) ||
                (actual_hit !== expected_hit) ||
                (actual_miss !== expected_miss) ||
                (actual_fault !== expected_fault)) begin
                $error(
                    "%s: addr=%08h write=%b funct3=%03b data=%08h/%08h hit=%b/%b miss=%b/%b fault=%b/%b",
                    test_name,
                    address,
                    write_request,
                    funct3,
                    actual_data,
                    expected_data,
                    actual_hit,
                    expected_hit,
                    actual_miss,
                    expected_miss,
                    actual_fault,
                    expected_fault
                );
                errors++;
            end
        end
    endtask

    task automatic check_response_backpressure();
        logic [31:0] expected_data;
        logic [31:0] held_data;
        logic held_hit;
        logic held_miss;
        logic held_fault;
        int timeout;

        begin
            expected_data = reference_load(32'h0000_0200, 3'b010);
            cpu_resp_ready = 1'b0;

            @(negedge clk);
            cpu_req_write  = 1'b0;
            cpu_req_addr   = 32'h0000_0200;
            cpu_req_wdata  = '0;
            cpu_req_funct3 = 3'b010;
            cpu_req_valid  = 1'b1;

            @(posedge clk);
            #1;
            @(negedge clk);
            cpu_req_valid = 1'b0;

            timeout = 0;
            while (!cpu_resp_valid) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 300)
                    $fatal(1, "Timeout in response-backpressure test");
            end

            held_data  = cpu_resp_rdata;
            held_hit   = cpu_resp_hit;
            held_miss  = cpu_resp_miss;
            held_fault = cpu_resp_fault;

            repeat (3) begin
                @(posedge clk);
                #1;

                if ((cpu_resp_valid !== 1'b1) ||
                    (cpu_resp_rdata !== held_data) ||
                    (cpu_resp_hit !== held_hit) ||
                    (cpu_resp_miss !== held_miss) ||
                    (cpu_resp_fault !== held_fault) ||
                    (cpu_req_ready !== 1'b0)) begin
                    $error("CPU response changed while backpressured");
                    errors++;
                end
            end

            tests++;

            if ((held_data !== expected_data) ||
                (held_hit !== 1'b0) ||
                (held_miss !== 1'b1) ||
                (held_fault !== 1'b0)) begin
                $error("Incorrect held response during CPU backpressure");
                errors++;
            end

            @(negedge clk);
            cpu_resp_ready = 1'b1;

            @(posedge clk);
            #1;

            if ((cpu_resp_valid !== 1'b0) ||
                (cpu_req_ready !== 1'b1)) begin
                $error("Cache did not return to idle after held response");
                errors++;
            end
        end
    endtask

    task automatic check_memory_backpressure();
        logic [31:0] expected_data;
        logic [31:0] held_address;
        logic [LINE_BITS-1:0] held_write_data;
        logic held_write;
        int timeout;

        begin
            expected_data = reference_load(32'h0000_0240, 3'b010);
            memory_accept_enable = 1'b0;

            @(negedge clk);
            cpu_req_write  = 1'b0;
            cpu_req_addr   = 32'h0000_0240;
            cpu_req_wdata  = '0;
            cpu_req_funct3 = 3'b010;
            cpu_req_valid  = 1'b1;

            @(posedge clk);
            #1;
            @(negedge clk);
            cpu_req_valid = 1'b0;

            timeout = 0;
            while (!mem_req_valid) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 100)
                    $fatal(1, "Timeout waiting for stalled memory request");
            end

            held_address    = mem_req_addr;
            held_write_data = mem_req_wdata;
            held_write      = mem_req_write;

            repeat (3) begin
                @(posedge clk);
                #1;

                if ((mem_req_valid !== 1'b1) ||
                    (mem_req_addr !== held_address) ||
                    (mem_req_wdata !== held_write_data) ||
                    (mem_req_write !== held_write)) begin
                    $error("Memory request changed while backpressured");
                    errors++;
                end
            end

            @(negedge clk);
            memory_accept_enable = 1'b1;

            timeout = 0;
            while (!cpu_resp_valid) begin
                @(posedge clk);
                #1;
                timeout++;
                if (timeout > 300)
                    $fatal(1, "Timeout after releasing memory backpressure");
            end

            tests++;

            if ((cpu_resp_rdata !== expected_data) ||
                (cpu_resp_hit !== 1'b0) ||
                (cpu_resp_miss !== 1'b1) ||
                (cpu_resp_fault !== 1'b0)) begin
                $error("Incorrect response after memory backpressure");
                errors++;
            end

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        tests  = 0;

        rst                  = 1'b0;
        cpu_req_valid        = 1'b0;
        cpu_req_write        = 1'b0;
        cpu_req_addr         = '0;
        cpu_req_wdata        = '0;
        cpu_req_funct3       = 3'b010;
        cpu_resp_ready       = 1'b1;
        memory_accept_enable = 1'b1;

        // Cold miss followed by a hit to another word in the same line.
        reset_environment();

        check_access(
            "cold word load",
            1'b0, 32'h0000_0020, '0, 3'b010,
            reference_load(32'h0000_0020, 3'b010),
            1'b0, 1'b1, 1'b0
        );

        check_access(
            "same-line word hit",
            1'b0, 32'h0000_0024, '0, 3'b010,
            reference_load(32'h0000_0024, 3'b010),
            1'b1, 1'b0, 1'b0
        );

        // Signed and unsigned byte/halfword formatting.
        backing_memory[16]   = 32'h80ff_7f01;
        reference_memory[16] = 32'h80ff_7f01;

        check_access(
            "LB cold miss",
            1'b0, 32'h0000_0040, '0, 3'b000,
            32'h0000_0001,
            1'b0, 1'b1, 1'b0
        );

        check_access(
            "LB sign extension",
            1'b0, 32'h0000_0042, '0, 3'b000,
            32'hffff_ffff,
            1'b1, 1'b0, 1'b0
        );

        check_access(
            "LBU zero extension",
            1'b0, 32'h0000_0042, '0, 3'b100,
            32'h0000_00ff,
            1'b1, 1'b0, 1'b0
        );

        check_access(
            "LH sign extension",
            1'b0, 32'h0000_0042, '0, 3'b001,
            32'hffff_80ff,
            1'b1, 1'b0, 1'b0
        );

        check_access(
            "LHU zero extension",
            1'b0, 32'h0000_0042, '0, 3'b101,
            32'h0000_80ff,
            1'b1, 1'b0, 1'b0
        );

        // Partial stores modify only the selected bytes and remain in the
        // dirty cache line until eviction.
        check_access(
            "SB hit",
            1'b1, 32'h0000_0041, 32'h0000_00aa, 3'b000,
            32'b0,
            1'b1, 1'b0, 1'b0
        );
        reference_store(32'h0000_0041, 3'b000, 32'h0000_00aa);

        check_access(
            "word after SB",
            1'b0, 32'h0000_0040, '0, 3'b010,
            reference_load(32'h0000_0040, 3'b010),
            1'b1, 1'b0, 1'b0
        );

        check_access(
            "SH hit",
            1'b1, 32'h0000_0042, 32'h0000_1234, 3'b001,
            32'b0,
            1'b1, 1'b0, 1'b0
        );
        reference_store(32'h0000_0042, 3'b001, 32'h0000_1234);

        check_access(
            "word after SH",
            1'b0, 32'h0000_0040, '0, 3'b010,
            reference_load(32'h0000_0040, 3'b010),
            1'b1, 1'b0, 1'b0
        );

        check_access(
            "SW same-line hit",
            1'b1, 32'h0000_0044, 32'hdead_beef, 3'b010,
            32'b0,
            1'b1, 1'b0, 1'b0
        );
        reference_store(32'h0000_0044, 3'b010, 32'hdead_beef);

        check_access(
            "word after SW",
            1'b0, 32'h0000_0044, '0, 3'b010,
            32'hdead_beef,
            1'b1, 1'b0, 1'b0
        );

        // Store miss must refill the line, merge the store, and mark it dirty.
        reset_environment();

        check_access(
            "write-allocate store miss",
            1'b1, 32'h0000_0100, 32'hcafe_f00d, 3'b010,
            32'b0,
            1'b0, 1'b1, 1'b0
        );
        reference_store(32'h0000_0100, 3'b010, 32'hcafe_f00d);

        check_access(
            "write-allocate load hit",
            1'b0, 32'h0000_0100, '0, 3'b010,
            32'hcafe_f00d,
            1'b1, 1'b0, 1'b0
        );

        if (backing_memory[32'h100 >> 2] === 32'hcafe_f00d) begin
            $error("Store hit wrote through before eviction");
            errors++;
        end

        // These directed replacement sequences intentionally describe a 2-way
        // set. Wider configurations still run all protocol, formatting, fault,
        // and randomized memory-model checks below.
        if (NUM_WAYS == 2) begin
            // Addresses separated by NUM_SETS * LINE_BYTES map to the same set.
            // Accessing A after filling A and B makes B the PLRU victim for C.
            reset_environment();

            check_access("PLRU fill A", 1'b0, 32'h0000_0000, '0, 3'b010,
                         reference_load(32'h0000_0000, 3'b010),
                         1'b0, 1'b1, 1'b0);
            check_access("PLRU fill B", 1'b0, 32'h0000_0040, '0, 3'b010,
                         reference_load(32'h0000_0040, 3'b010),
                         1'b0, 1'b1, 1'b0);
            check_access("PLRU touch A", 1'b0, 32'h0000_0000, '0, 3'b010,
                         reference_load(32'h0000_0000, 3'b010),
                         1'b1, 1'b0, 1'b0);
            check_access("PLRU replace B with C", 1'b0, 32'h0000_0080, '0, 3'b010,
                         reference_load(32'h0000_0080, 3'b010),
                         1'b0, 1'b1, 1'b0);
            check_access("PLRU A survives", 1'b0, 32'h0000_0000, '0, 3'b010,
                         reference_load(32'h0000_0000, 3'b010),
                         1'b1, 1'b0, 1'b0);
            check_access("PLRU B was evicted", 1'b0, 32'h0000_0040, '0, 3'b010,
                         reference_load(32'h0000_0040, 3'b010),
                         1'b0, 1'b1, 1'b0);

            // Dirty victim must be written back before the incoming line refills.
            reset_environment();

            check_access("dirty fill D", 1'b1, 32'h0000_0100,
                         32'h1122_3344, 3'b010, 32'b0,
                         1'b0, 1'b1, 1'b0);
            reference_store(32'h0000_0100, 3'b010, 32'h1122_3344);

            check_access("clean fill E", 1'b0, 32'h0000_0140, '0, 3'b010,
                         reference_load(32'h0000_0140, 3'b010),
                         1'b0, 1'b1, 1'b0);

            check_access("dirty eviction by F", 1'b0, 32'h0000_0180, '0, 3'b010,
                         reference_load(32'h0000_0180, 3'b010),
                         1'b0, 1'b1, 1'b0);

            tests++;
            if ((memory_write_requests !== 1) ||
                (backing_memory[32'h100 >> 2] !== 32'h1122_3344)) begin
                $error(
                    "Dirty eviction failed: writes=%0d backing=%08h",
                    memory_write_requests,
                    backing_memory[32'h100 >> 2]
                );
                errors++;
            end

            check_access("reload written-back D", 1'b0, 32'h0000_0100, '0, 3'b010,
                         32'h1122_3344,
                         1'b0, 1'b1, 1'b0);
        end

        // Malformed or misaligned requests fail without accessing memory.
        reset_environment();

        check_access("misaligned LW", 1'b0, 32'h0000_0002, '0, 3'b010,
                     32'b0, 1'b0, 1'b0, 1'b1);
        check_access("misaligned LH", 1'b0, 32'h0000_0001, '0, 3'b001,
                     32'b0, 1'b0, 1'b0, 1'b1);
        check_access("illegal load funct3", 1'b0, 32'h0000_0000, '0, 3'b011,
                     32'b0, 1'b0, 1'b0, 1'b1);
        check_access("illegal store funct3", 1'b1, 32'h0000_0000, '0, 3'b111,
                     32'b0, 1'b0, 1'b0, 1'b1);

        tests++;
        if ((memory_read_requests !== 0) ||
            (memory_write_requests !== 0)) begin
            $error("Faulting requests reached backing memory");
            errors++;
        end

        reset_environment();
        check_response_backpressure();

        reset_environment();
        check_memory_backpressure();

        // Random legal loads and stores are compared against the independent
        // architectural memory model. Repeated conflicts naturally exercise
        // clean and dirty replacement paths.
        reset_environment();

        for (int test_index = 0;
             test_index < NUM_RANDOM_TESTS;
             test_index++) begin
            logic write_request;
            logic [31:0] address;
            logic [31:0] write_data;
            logic [2:0] funct3;
            logic [31:0] actual_data;
            logic actual_hit;
            logic actual_miss;
            logic actual_fault;
            int word_index;

            write_request = $urandom_range(0, 1);
            write_data    = $urandom;
            word_index    = $urandom_range(0, MEM_WORDS - 1);

            if (write_request) begin
                case ($urandom_range(0, 2))
                    0: begin
                        funct3 = 3'b000;
                        address = (word_index << 2) +
                                  $urandom_range(0, 3);
                    end
                    1: begin
                        funct3 = 3'b001;
                        address = (word_index << 2) +
                                  (2 * $urandom_range(0, 1));
                    end
                    default: begin
                        funct3 = 3'b010;
                        address = word_index << 2;
                    end
                endcase
            end
            else begin
                case ($urandom_range(0, 4))
                    0: begin
                        funct3 = 3'b000;
                        address = (word_index << 2) +
                                  $urandom_range(0, 3);
                    end
                    1: begin
                        funct3 = 3'b001;
                        address = (word_index << 2) +
                                  (2 * $urandom_range(0, 1));
                    end
                    2: begin
                        funct3 = 3'b010;
                        address = word_index << 2;
                    end
                    3: begin
                        funct3 = 3'b100;
                        address = (word_index << 2) +
                                  $urandom_range(0, 3);
                    end
                    default: begin
                        funct3 = 3'b101;
                        address = (word_index << 2) +
                                  (2 * $urandom_range(0, 1));
                    end
                endcase
            end

            cpu_access(
                write_request,
                address,
                write_data,
                funct3,
                actual_data,
                actual_hit,
                actual_miss,
                actual_fault
            );

            tests++;

            if (actual_fault || (actual_hit == actual_miss)) begin
                $error(
                    "Random request %0d returned invalid status hit/miss/fault=%b/%b/%b",
                    test_index,
                    actual_hit,
                    actual_miss,
                    actual_fault
                );
                errors++;
            end

            if (write_request) begin
                if (actual_data !== 32'b0) begin
                    $error("Random store %0d returned nonzero data %08h",
                           test_index, actual_data);
                    errors++;
                end

                reference_store(address, funct3, write_data);
            end
            else if (actual_data !== reference_load(address, funct3)) begin
                $error(
                    "Random load %0d: addr=%08h funct3=%03b expected=%08h actual=%08h",
                    test_index,
                    address,
                    funct3,
                    reference_load(address, funct3),
                    actual_data
                );
                errors++;
            end
        end

        if (errors == 0)
            $display(
                "PASS: dcache_tb (%0d-way, %0d checks, %0d random requests)",
                NUM_WAYS,
                tests,
                NUM_RANDOM_TESTS
            );
        else
            $fatal(1,
                   "FAIL: dcache_tb had %0d errors across %0d checks",
                   errors,
                   tests);

        $finish;
    end

endmodule
