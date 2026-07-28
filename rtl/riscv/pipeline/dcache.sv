// dcache.sv -- parameterized set-associative data cache

// Policy:
//   - Set associative
//   - Write-back
//   - Write-allocate
//   - Tree pseudo-LRU replacement
//   - One outstanding CPU request at a time
//
// Default organization:
//   - 16 sets
//   - 2 ways per set
//   - 4 words per cache line
//   - 32-bit CPU words
//
// CPU protocol:
//   1. The CPU raises cpu_req_valid.
//   2. The cache accepts the request when cpu_req_ready is also high.
//   3. The cache later raises cpu_resp_valid.
//   4. The response remains stable until cpu_resp_ready is high.
//
// Memory protocol:
//   - Refill reads and dirty writebacks transfer an entire cache line.
// =============================================================================

module dcache #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_SETS   = 16,
    parameter int NUM_WAYS   = 2,
    parameter int LINE_WORDS = 4
) (
    input logic clk,
    input logic rst,

    // -------------------------------------------------------------------------
    // CPU request
    // -------------------------------------------------------------------------

    input  logic                  cpu_req_valid,
    input  logic                  cpu_req_write,
    input  logic [ADDR_WIDTH-1:0] cpu_req_addr,
    input  logic [DATA_WIDTH-1:0] cpu_req_wdata,
    input  logic [2:0]            cpu_req_funct3,

    output logic                  cpu_req_ready,


    // -------------------------------------------------------------------------
    // CPU response
    // -------------------------------------------------------------------------

    input  logic                  cpu_resp_ready,

    output logic                  cpu_resp_valid,
    output logic [DATA_WIDTH-1:0] cpu_resp_rdata,
    output logic                  cpu_resp_hit,
    output logic                  cpu_resp_miss,
    output logic                  cpu_resp_fault,

    // -------------------------------------------------------------------------
    // Backing-memory line request
    // -------------------------------------------------------------------------

    input  logic                             mem_req_ready,

    output logic                             mem_req_valid,
    output logic                             mem_req_write,
    output logic [ADDR_WIDTH-1:0]            mem_req_addr,
    output logic [(DATA_WIDTH*LINE_WORDS)-1:0] mem_req_wdata,

    // -------------------------------------------------------------------------
    // Backing-memory refill response
    // -------------------------------------------------------------------------

    input  logic                             mem_resp_valid,
    input  logic [(DATA_WIDTH*LINE_WORDS)-1:0] mem_resp_rdata,
    input  logic                             mem_resp_fault,

    output logic                             mem_resp_ready

);

    localparam int BYTES_PER_WORD  = DATA_WIDTH / 8;
    localparam int LINE_BYTES      = LINE_WORDS * BYTES_PER_WORD;
    localparam int LINE_BITS       = LINE_WORDS * DATA_WIDTH;

    localparam int BYTE_OFFSET_BITS = $clog2(BYTES_PER_WORD);
    localparam int WORD_OFFSET_BITS = $clog2(LINE_WORDS);
    localparam int LINE_OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int SET_INDEX_BITS   = $clog2(NUM_SETS);
    localparam int WAY_INDEX_BITS   = $clog2(NUM_WAYS);
    localparam int TAG_BITS         = ADDR_WIDTH - SET_INDEX_BITS - LINE_OFFSET_BITS;

    typedef logic [SET_INDEX_BITS-1:0] set_index_t;
    typedef logic [WAY_INDEX_BITS-1:0] way_index_t;
    typedef logic [TAG_BITS-1:0]       tag_t;

    typedef enum logic [2:0] {
        CACHE_IDLE,
        CACHE_LOOKUP,
        CACHE_STORE_HIT,
        CACHE_WRITEBACK,
        CACHE_REFILL_REQUEST,
        CACHE_REFILL_WAIT,
        CACHE_RESPONSE
    } cache_state_t;

    cache_state_t state;

    // -------------------------------------------------------------------------
    // Cache arrays (actual storage for the inside the cache)
    // -------------------------------------------------------------------------

    // cache line data, addr tag, valid, and dirty/modified flags
    logic [LINE_BITS-1:0] data_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    tag_t tag_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];

    // -------------------------------------------------------------------------
    // Saved CPU request
    // -------------------------------------------------------------------------

    logic                  req_write;
    logic [ADDR_WIDTH-1:0] req_addr;
    logic [DATA_WIDTH-1:0] req_wdata;
    logic [2:0]            req_funct3;
    logic                  req_fault;

    set_index_t req_set;
    logic [WORD_OFFSET_BITS-1:0] req_word_offset;
    logic [BYTE_OFFSET_BITS-1:0] req_byte_offset;
    tag_t req_tag;

    // Victim chosen when the request misses.
    way_index_t victim_way;

    // A store hit registers its selected way before modifying the line. This
    // breaks the tag-compare-to-cache-line-write timing path.
    way_index_t store_hit_way;

    // -------------------------------------------------------------------------
    // Saved CPU response
    // -------------------------------------------------------------------------

    logic                  response_valid;
    logic [DATA_WIDTH-1:0] response_data;
    logic                  response_hit;
    logic                  response_miss;
    logic                  response_fault;

    assign cpu_resp_valid = response_valid;
    assign cpu_resp_rdata = response_data;
    assign cpu_resp_hit   = response_hit;
    assign cpu_resp_miss  = response_miss;
    assign cpu_resp_fault = response_fault;

    // The blocking cache accepts a new request only when it is idle.
    assign cpu_req_ready = (state == CACHE_IDLE);

    // -------------------------------------------------------------------------
    // Address breakdown
    // -------------------------------------------------------------------------

    assign req_byte_offset = req_addr[BYTE_OFFSET_BITS-1:0];
    assign req_word_offset = req_addr[BYTE_OFFSET_BITS +: WORD_OFFSET_BITS];
    assign req_set = req_addr[LINE_OFFSET_BITS +: SET_INDEX_BITS];
    assign req_tag = req_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // -------------------------------------------------------------------------
    // Helper functions
    // -------------------------------------------------------------------------

    function automatic logic is_power_of_two(input int value);
        is_power_of_two = (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    // Check whether funct3 represents a legal RV32 load or store operation.
    function automatic logic encoding_valid(
        input logic       write_request,
        input logic [2:0] funct3
    );
        begin
            encoding_valid = 1'b0;

            if (write_request) begin //CPU requesting a store
                case (funct3)
                    3'b000, // SB
                    3'b001, // SH
                    3'b010: encoding_valid = 1'b1; // SW
                    default: encoding_valid = 1'b0;
                endcase
            end
            else begin
                case (funct3)
                    3'b000, // LB
                    3'b001, // LH
                    3'b010, // LW
                    3'b100, // LBU (Load Byte Unsigned)
                    3'b101: encoding_valid = 1'b1; // LHU
                    default: encoding_valid = 1'b0;
                endcase
            end
        end
    endfunction

    // Check address alignment for the requested byte, halfword, or word access.
    function automatic logic address_aligned(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [2:0]            funct3
    );
        begin
            case (funct3[1:0])
                2'b00: address_aligned = 1'b1; //no alignment restriction for one byte access
                2'b01: address_aligned = (address[0] == 1'b0); //halfword is two bytes wide so the addr has to be /2
                2'b10: address_aligned = (address[1:0] == 2'b00); //word is 4 bytes wide so addr has to be /4
                default: address_aligned = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] read_word(
        input logic [LINE_BITS-1:0] line,
        input way_index_t           unused_way,
        input logic [WORD_OFFSET_BITS-1:0] word_offset
    );
        int first_bit;

        begin
            // unused_way keeps this helper's call sites readable while the
            // actual way selection remains outside the function.
            first_bit = int'(word_offset) * DATA_WIDTH;
            read_word = line[first_bit +: DATA_WIDTH];
        end
    endfunction

    function automatic logic [LINE_BITS-1:0] write_word(
        input logic [LINE_BITS-1:0] line,
        input logic [WORD_OFFSET_BITS-1:0] word_offset,
        input logic [DATA_WIDTH-1:0] new_word
    );
        logic [LINE_BITS-1:0] updated_line;
        int first_bit;

        begin
            updated_line = line;
            first_bit = int'(word_offset) * DATA_WIDTH;

            updated_line[first_bit +: DATA_WIDTH] = new_word;
            write_word = updated_line;
        end
    endfunction

    //takes a complete cache line modifies the byte, halfword, or word targeted
    //by a store instruction and returns the updated cache line (SB, SH, SW)
    function automatic logic [LINE_BITS-1:0] apply_store(
        input logic [LINE_BITS-1:0] line,
        input logic [WORD_OFFSET_BITS-1:0] word_offset,
        input logic [BYTE_OFFSET_BITS-1:0] byte_offset,
        input logic [2:0] funct3,
        input logic [DATA_WIDTH-1:0] write_data
    );
        logic [DATA_WIDTH-1:0] current_word;
        int byte_position;

        begin
            current_word = line[int'(word_offset) * DATA_WIDTH +: DATA_WIDTH];

            byte_position = int'(byte_offset) * 8;

            case (funct3)
                3'b000: //byte
                    current_word[byte_position +: 8] = write_data[7:0];

                3'b001: //halfword
                    current_word[byte_position +: 16] = write_data[15:0];

                3'b010: //word
                    current_word = write_data;

                default:
                    current_word = current_word;
            endcase

            apply_store = write_word(line, word_offset, current_word);
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] format_load(
        input logic [DATA_WIDTH-1:0] word,
        input logic [BYTE_OFFSET_BITS-1:0] byte_offset,
        input logic [2:0] funct3
    );
        logic [7:0]  selected_byte;
        logic [15:0] selected_half;
        int byte_position;

        begin
            byte_position = int'(byte_offset) * 8;

            selected_byte = word[byte_position +: 8];
            selected_half =
                byte_offset[1] ? word[31:16] : word[15:0];

            case (funct3)
                3'b000: //LB
                    format_load = {{24{selected_byte[7]}}, selected_byte};

                3'b001: //LH
                    format_load = {{16{selected_half[15]}}, selected_half};

                3'b010: //LW
                    format_load = word;

                3'b100: //LBU
                    format_load = {24'b0, selected_byte};

                3'b101: //LHU
                    format_load = {16'b0, selected_half};

                default:
                    format_load = '0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Hit and victim selection
    // -------------------------------------------------------------------------

    logic       cache_hit;
    way_index_t hit_way;
    way_index_t plru_victim;

    always_comb begin
        cache_hit = 1'b0;
        hit_way   = '0;

        for (int way = 0; way < NUM_WAYS; way++) begin
            if (valid_array[req_set][way] && (tag_array[req_set][way] == req_tag)) begin
                cache_hit = 1'b1;
                hit_way   = way_index_t'(way);
            end
        end
    end

    way_index_t selected_victim;

    always_comb begin : choose_victim
        logic found_invalid;

        selected_victim = plru_victim;
        found_invalid   = 1'b0;

        // Empty ways are used before a valid line is evicted.
        for (int way = 0; way < NUM_WAYS; way++) begin
            if (!found_invalid && !valid_array[req_set][way]) begin
                selected_victim = way_index_t'(way);
                found_invalid   = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Data selected for hits and refills
    // -------------------------------------------------------------------------

    logic [LINE_BITS-1:0] hit_line;
    logic [DATA_WIDTH-1:0] hit_read_data;

    logic [LINE_BITS-1:0] store_hit_line;
    logic [LINE_BITS-1:0] store_hit_line_after_store;

    logic [LINE_BITS-1:0] refill_line;
    logic [DATA_WIDTH-1:0] refill_read_data;

    always_comb begin
        hit_line = data_array[req_set][hit_way];

        hit_read_data = format_load(
            read_word(hit_line, hit_way, req_word_offset),
            req_byte_offset,
            req_funct3
        );

        // The way was registered in CACHE_LOOKUP, so this update no longer
        // depends combinationally on the tag comparison.
        store_hit_line = data_array[req_set][store_hit_way];
        store_hit_line_after_store = apply_store(
            store_hit_line,
            req_word_offset,
            req_byte_offset,
            req_funct3,
            req_wdata
        );

        refill_line = mem_resp_rdata;

        if (req_write) begin
            refill_line = apply_store(
                mem_resp_rdata,
                req_word_offset,
                req_byte_offset,
                req_funct3,
                req_wdata
            );
        end

        refill_read_data = format_load(
            read_word(refill_line, victim_way, req_word_offset),
            req_byte_offset,
            req_funct3
        );
    end

    // -------------------------------------------------------------------------
    // PLRU replacement state
    // -------------------------------------------------------------------------

    logic       plru_update;
    set_index_t plru_update_set;
    way_index_t plru_accessed_way;

    always_comb begin
        plru_update       = 1'b0;
        plru_update_set   = req_set;
        plru_accessed_way = hit_way;

        if ((state == CACHE_LOOKUP) && !req_fault && cache_hit) begin
            plru_update       = 1'b1;
            plru_accessed_way = hit_way;
        end
        else if ((state == CACHE_REFILL_WAIT) &&
                 mem_resp_valid &&
                 mem_resp_ready &&
                 !mem_resp_fault) begin
            plru_update       = 1'b1;
            plru_accessed_way = victim_way;
        end
    end

    plru #(
        .NUM_SETS(NUM_SETS),
        .NUM_WAYS(NUM_WAYS)
    ) u_plru (
        .clk         (clk),
        .rst         (rst),
        .lookup_set  (req_set),
        .victim_way  (plru_victim),
        .update      (plru_update),
        .update_set  (plru_update_set),
        .accessed_way(plru_accessed_way)
    );

    // -------------------------------------------------------------------------
    // Backing-memory request generation
    // -------------------------------------------------------------------------

    always_comb begin
        mem_req_valid  = 1'b0;
        mem_req_write  = 1'b0;
        mem_req_addr   = '0;
        mem_req_wdata  = '0;
        mem_resp_ready = 1'b0;

        if (state == CACHE_WRITEBACK) begin
            mem_req_valid = 1'b1;
            mem_req_write = 1'b1;

            mem_req_addr = {
                tag_array[req_set][victim_way],
                req_set,
                {LINE_OFFSET_BITS{1'b0}}
            };

            mem_req_wdata = data_array[req_set][victim_way];
        end
        else if (state == CACHE_REFILL_REQUEST) begin
            mem_req_valid = 1'b1;
            mem_req_write = 1'b0;

            mem_req_addr = {
                req_tag,
                req_set,
                {LINE_OFFSET_BITS{1'b0}}
            };
        end
        else if (state == CACHE_REFILL_WAIT)
            mem_resp_ready = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Parameter checks
    // -------------------------------------------------------------------------

    initial begin
        if (DATA_WIDTH != 32) $fatal(1, "This RV32 D-cache requires DATA_WIDTH = 32");
        if (!is_power_of_two(NUM_SETS)) $fatal(1, "NUM_SETS must be a power of two");
        if (!is_power_of_two(NUM_WAYS)) $fatal(1, "NUM_WAYS must be a power of two");
        if (!is_power_of_two(LINE_WORDS)) $fatal(1, "LINE_WORDS must be a power of two");
        if (NUM_SETS < 2) $fatal(1, "NUM_SETS must be at least two");
        if (NUM_WAYS < 2) $fatal(1, "NUM_WAYS must be at least two");
        if (LINE_WORDS < 2) $fatal(1, "LINE_WORDS must be at least two");
    end

    /*
        CACHE_IDLE
            |
            v
        CACHE_LOOKUP -- fault or hit --------------------> CACHE_RESPONSE
            |
            +-- store hit --> CACHE_STORE_HIT ----------> CACHE_RESPONSE
            |
            +-- clean miss --> CACHE_REFILL_REQUEST
            |
            +-- dirty miss --> CACHE_WRITEBACK
                                   |
                                   v
                              CACHE_REFILL_REQUEST
                                   |
                                   v
                              CACHE_REFILL_WAIT
                                   |
                                   v
                              CACHE_RESPONSE
                                   |
                                   v
                              CACHE_IDLE




        CACHE_IDLE:
            Waits for a new CPU load or store request.

        CACHE_LOOKUP:
            Examines the saved CPU request and determines whether the access is faulty,
            a cache hit, or a cache miss.

        CACHE_STORE_HIT:
            Updates the line selected by the previous cycle's tag lookup. The
            registered way removes tag comparison from the line-write path.

        CACHE_WRITEBACK:
            Used only on a cache miss when the selected victim line is dirty.
            The cache writes the old dirty line back to memory before replacing it.

        CACHE_REFILL_REQUEST:
            Sends a memory read request for the cache line containing the CPU’s requested address.

        CACHE_REFILL_WAIT:
            Waits for memory to return the requested cache line after the refill request has been accepted.
    */


    // -------------------------------------------------------------------------
    // Cache controller
    // -------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= CACHE_IDLE;

            req_write  <= 1'b0;
            req_addr   <= '0;
            req_wdata  <= '0;
            req_funct3 <= '0;
            req_fault  <= 1'b0;
            victim_way <= '0;
            store_hit_way <= '0;

            response_valid <= 1'b0;
            response_data  <= '0;
            response_hit   <= 1'b0;
            response_miss  <= 1'b0;
            response_fault <= 1'b0;

            // Only metadata needs reset. Invalid cache-line data is ignored,
            // so clearing the entire data array would waste FPGA resources.
            for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
                for (int way = 0; way < NUM_WAYS; way++) begin
                    valid_array[set_index][way] <= 1'b0;
                    dirty_array[set_index][way] <= 1'b0;
                    tag_array[set_index][way]   <= '0;
                end
            end
        end
        else begin
            case (state)
                CACHE_IDLE: begin
                    if (cpu_req_valid && cpu_req_ready) begin
                        req_write  <= cpu_req_write;
                        req_addr   <= cpu_req_addr;
                        req_wdata  <= cpu_req_wdata;
                        req_funct3 <= cpu_req_funct3;

                        req_fault <=
                            !encoding_valid(
                                cpu_req_write,
                                cpu_req_funct3
                            ) ||
                            !address_aligned(
                                cpu_req_addr,
                                cpu_req_funct3
                            );

                        state <= CACHE_LOOKUP;
                    end
                end

                CACHE_LOOKUP: begin
                    if (req_fault) begin
                        response_valid <= 1'b1;
                        response_data  <= '0;
                        response_hit   <= 1'b0;
                        response_miss  <= 1'b0;
                        response_fault <= 1'b1;

                        state <= CACHE_RESPONSE;
                    end
                    else if (cache_hit) begin
                        if (req_write) begin
                            store_hit_way <= hit_way;
                            state <= CACHE_STORE_HIT;
                        end
                        else begin
                            response_valid <= 1'b1;
                            response_data  <= hit_read_data;
                            response_hit   <= 1'b1;
                            response_miss  <= 1'b0;
                            response_fault <= 1'b0;

                            state <= CACHE_RESPONSE;
                        end
                    end
                    else begin
                        victim_way <= selected_victim;

                        if (valid_array[req_set][selected_victim] &&
                            dirty_array[req_set][selected_victim])
                            state <= CACHE_WRITEBACK;
                        else
                            state <= CACHE_REFILL_REQUEST;
                    end
                end

                CACHE_STORE_HIT: begin
                    data_array[req_set][store_hit_way] <=
                        store_hit_line_after_store;
                    dirty_array[req_set][store_hit_way] <= 1'b1;

                    response_valid <= 1'b1;
                    response_data  <= '0;
                    response_hit   <= 1'b1;
                    response_miss  <= 1'b0;
                    response_fault <= 1'b0;

                    state <= CACHE_RESPONSE;
                end

                CACHE_WRITEBACK: begin
                    // A dirty line must be written to memory before eviction.
                    if (mem_req_valid && mem_req_ready) state <= CACHE_REFILL_REQUEST;
                end

                CACHE_REFILL_REQUEST: begin
                    // After memory accepts the read request, wait for its line.
                    if (mem_req_valid && mem_req_ready) state <= CACHE_REFILL_WAIT;
                end

                CACHE_REFILL_WAIT: begin
                    if (mem_resp_valid && mem_resp_ready) begin
                        response_valid <= 1'b1;
                        response_hit   <= 1'b0;
                        response_miss  <= 1'b1;

                        if (mem_resp_fault) begin
                            // Do not install or dirty a line that backing
                            // memory reported as inaccessible.
                            response_data  <= '0;
                            response_fault <= 1'b1;
                        end
                        else begin
                            data_array[req_set][victim_way] <= refill_line;

                            valid_array[req_set][victim_way] <= 1'b1;
                            dirty_array[req_set][victim_way] <= req_write;
                            tag_array[req_set][victim_way]   <= req_tag;

                            response_data  <= req_write ? '0 : refill_read_data;
                            response_fault <= 1'b0;
                        end

                        state <= CACHE_RESPONSE;
                    end
                end

                CACHE_RESPONSE: begin
                    // Hold the response until the processor accepts it.
                    if (response_valid && cpu_resp_ready) begin
                        response_valid <= 1'b0;
                        response_hit   <= 1'b0;
                        response_miss  <= 1'b0;
                        response_fault <= 1'b0;

                        state <= CACHE_IDLE;
                    end
                end

                default: begin
                    response_valid <= 1'b0;
                    state          <= CACHE_IDLE;
                end
            endcase
        end
    end

endmodule
