// icache.sv -- parameterized direct-mapped instruction cache

// Adapted from the CacheTime direct_mapped_cache: the tag/index/offset
// address breakdown and the refill state machine are kept, while every
// store-related feature (write port, byte enables, dirty bits, writeback)
// is stripped because the fetch side only ever reads.

// Policy:
//   - Direct mapped (one way per set)
//   - Read-only from the CPU side
//   - Misses perform a clean full-line refill from backing memory
//   - One outstanding refill at a time

// Default organization:
//   - 16 sets
//   - 4 words per cache line
//   - 32-bit instructions

// Fetch protocol (flow-through, so a hit behaves exactly like the
// combinational imem the IF stage uses today):
//   1. The fetch stage presents the live PC on cpu_req_addr with
//      cpu_req_valid high.
//   2. On a hit, cpu_resp_valid rises in the SAME cycle and cpu_resp_rdata
//      holds the instruction. cpu_stall stays low, so hits cost zero extra
//      cycles.
//   3. On a miss, cpu_stall rises in the same cycle. The fetch stage must
//      freeze PC and IF/ID while cpu_stall is high (wire it into pc_stall /
//      stall_if_id). When the refill line is installed the frozen PC hits
//      and cpu_stall drops.
//   4. A misaligned fetch reports cpu_resp_fault with a NOP and never
//      touches memory, mirroring imem's access_fault behavior.
//
// The miss address is latched when the refill starts, so the refill
// completes correctly even if cpu_req_addr changes mid-refill (the new
// address is simply looked up fresh once the cache returns to LOOKUP).

// Memory protocol:
//   - Refill reads transfer an entire cache line, using the same
//     valid/ready handshake as the dcache. There is no memory write path.

module icache
    import rv32i_pkg::*;
#(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_SETS   = 16,
    parameter int LINE_WORDS = 4
) (
    input logic clk,
    input logic rst,

    // -------------------------------------------------------------------------
    // CPU fetch request (live PC, not registered by the cache)
    // -------------------------------------------------------------------------

    input  logic                  cpu_req_valid,
    input  logic [ADDR_WIDTH-1:0] cpu_req_addr,

    // -------------------------------------------------------------------------
    // CPU fetch response (same cycle on a hit)
    // -------------------------------------------------------------------------

    output logic                  cpu_resp_valid,
    output logic [DATA_WIDTH-1:0] cpu_resp_rdata,
    output logic                  cpu_resp_fault,
    output logic                  cpu_stall,

    // -------------------------------------------------------------------------
    // Backing-memory line request (refill reads only)
    // -------------------------------------------------------------------------

    input  logic                             mem_req_ready,

    output logic                             mem_req_valid,
    output logic [ADDR_WIDTH-1:0]            mem_req_addr,

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
    localparam int TAG_BITS         = ADDR_WIDTH - SET_INDEX_BITS - LINE_OFFSET_BITS;

    typedef logic [SET_INDEX_BITS-1:0] set_index_t;
    typedef logic [TAG_BITS-1:0]       tag_t;

    typedef enum logic [1:0] {
        ICACHE_LOOKUP,
        ICACHE_REFILL_REQUEST,
        ICACHE_REFILL_WAIT,
        ICACHE_FAULT_RESPONSE
    } icache_state_t;

    icache_state_t state;

    // -------------------------------------------------------------------------
    // Cache arrays (one way per set: direct mapped)
    // -------------------------------------------------------------------------

    logic [LINE_BITS-1:0] data_array [0:NUM_SETS-1];
    tag_t tag_array [0:NUM_SETS-1];
    logic valid_array [0:NUM_SETS-1];

    // -------------------------------------------------------------------------
    // Live-address breakdown (hit check runs on the un-latched PC)
    // -------------------------------------------------------------------------

    set_index_t fetch_set;
    tag_t fetch_tag;
    logic [WORD_OFFSET_BITS-1:0] fetch_word_offset;

    assign fetch_word_offset = cpu_req_addr[BYTE_OFFSET_BITS +: WORD_OFFSET_BITS];
    assign fetch_set = cpu_req_addr[LINE_OFFSET_BITS +: SET_INDEX_BITS];
    assign fetch_tag = cpu_req_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // -------------------------------------------------------------------------
    // Saved miss address (stable for the whole refill sequence)
    // -------------------------------------------------------------------------

    logic [ADDR_WIDTH-1:0] req_addr;

    set_index_t req_set;
    tag_t req_tag;

    assign req_set = req_addr[LINE_OFFSET_BITS +: SET_INDEX_BITS];
    assign req_tag = req_addr[ADDR_WIDTH-1 -: TAG_BITS];

    // -------------------------------------------------------------------------
    // Hit and fault detection
    // -------------------------------------------------------------------------

    logic cache_hit;
    logic fetch_fault;

    assign cache_hit = valid_array[fetch_set] &&
                       (tag_array[fetch_set] == fetch_tag);

    // RV32I instructions are word aligned. A misaligned PC faults instead of
    // fetching, exactly like imem.
    assign fetch_fault = (cpu_req_addr[BYTE_OFFSET_BITS-1:0] != '0);

    // -------------------------------------------------------------------------
    // Helper functions
    // -------------------------------------------------------------------------

    function automatic logic is_power_of_two(input int value);
        is_power_of_two = (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] read_word(
        input logic [LINE_BITS-1:0] line,
        input logic [WORD_OFFSET_BITS-1:0] word_offset
    );
        int first_bit;

        begin
            first_bit = int'(word_offset) * DATA_WIDTH;
            read_word = line[first_bit +: DATA_WIDTH];
        end
    endfunction

    // -------------------------------------------------------------------------
    // CPU response (combinational, so hits look like imem to the IF stage)
    // -------------------------------------------------------------------------

    always_comb begin
        cpu_resp_valid = 1'b0;
        cpu_resp_rdata = INSTRUCTION_NOP;
        cpu_resp_fault = 1'b0;
        cpu_stall      = 1'b0;

        if (cpu_req_valid) begin
            if (state == ICACHE_FAULT_RESPONSE) begin
                // A backing-memory fault completes the frozen fetch with a
                // NOP. The fault bit travels with it and suppresses effects.
                cpu_resp_valid = 1'b1;
                cpu_resp_fault = 1'b1;
            end
            else if (state != ICACHE_LOOKUP) begin
                // A refill is in flight: keep the front of the pipe frozen.
                cpu_stall = 1'b1;
            end
            else if (fetch_fault) begin
                // Faulting fetches complete immediately with a NOP so the
                // fault can flow down the pipe instead of hanging fetch.
                cpu_resp_valid = 1'b1;
                cpu_resp_fault = 1'b1;
            end
            else if (cache_hit) begin
                cpu_resp_valid = 1'b1;
                cpu_resp_rdata = read_word(data_array[fetch_set],
                                           fetch_word_offset);
            end
            else begin
                // Miss detected this cycle: stall now, start the refill at
                // the next clock edge.
                cpu_stall = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Backing-memory request generation
    // -------------------------------------------------------------------------

    always_comb begin
        mem_req_valid  = 1'b0;
        mem_req_addr   = '0;
        mem_resp_ready = 1'b0;

        if (state == ICACHE_REFILL_REQUEST) begin
            mem_req_valid = 1'b1;

            mem_req_addr = {
                req_tag,
                req_set,
                {LINE_OFFSET_BITS{1'b0}}
            };
        end
        else if (state == ICACHE_REFILL_WAIT)
            mem_resp_ready = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Parameter checks
    // -------------------------------------------------------------------------

    initial begin
        if (DATA_WIDTH != 32) $fatal(1, "This RV32 I-cache requires DATA_WIDTH = 32");
        if (!is_power_of_two(NUM_SETS)) $fatal(1, "NUM_SETS must be a power of two");
        if (!is_power_of_two(LINE_WORDS)) $fatal(1, "LINE_WORDS must be a power of two");
        if (NUM_SETS < 2) $fatal(1, "NUM_SETS must be at least two");
        if (LINE_WORDS < 2) $fatal(1, "LINE_WORDS must be at least two");
    end

    /*
            Hit (or fault): answered combinationally, no state change
                    |
            Miss: latch the PC and stall the fetch stage
                    |
            Request the line from memory
                    |
            Install the returned line
                    |
            Frozen PC now hits and the stall drops


                ICACHE_LOOKUP  <────────────────┐
                    │ miss                      │
                    ▼                           │
                ICACHE_REFILL_REQUEST           │
                    │ memory accepted           │
                    ▼                           │
                ICACHE_REFILL_WAIT ─────────────┘
                      line installed

        ICACHE_LOOKUP: Serves hits and faults combinationally while watching
                       for a miss. This folds CacheTime's IDLE and LOOKUP
                       states together because fetch cannot afford a
                       two-cycle hit.
        ICACHE_REFILL_REQUEST: Asks memory for the line containing the missed
                       PC; the request holds until memory accepts it.
        ICACHE_REFILL_WAIT: Waits for memory to return the line, installs it,
                       and returns to lookup. There is no writeback state:
                       instruction lines are never dirty, so eviction is
                       just an overwrite.
    */

    // -------------------------------------------------------------------------
    // Cache controller
    // -------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ICACHE_LOOKUP;

            req_addr <= '0;

            // Only metadata needs reset. Invalid cache-line data is ignored,
            // so clearing the entire data array would waste FPGA resources.
            for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
                valid_array[set_index] <= 1'b0;
                tag_array[set_index]   <= '0;
            end
        end
        else begin
            case (state)
                ICACHE_LOOKUP: begin
                    // Hits and faults complete combinationally and need no
                    // state change. Only a valid, aligned miss starts a
                    // refill.
                    if (cpu_req_valid && !fetch_fault && !cache_hit) begin
                        req_addr <= cpu_req_addr;
                        state    <= ICACHE_REFILL_REQUEST;
                    end
                end

                ICACHE_REFILL_REQUEST: begin
                    // After memory accepts the read request, wait for its line.
                    if (mem_req_valid && mem_req_ready) state <= ICACHE_REFILL_WAIT;
                end

                ICACHE_REFILL_WAIT: begin
                    if (mem_resp_valid && mem_resp_ready) begin
                        if (mem_resp_fault)
                            state <= ICACHE_FAULT_RESPONSE;
                        else begin
                            data_array[req_set]  <= mem_resp_rdata;
                            valid_array[req_set] <= 1'b1;
                            tag_array[req_set]   <= req_tag;
                            state                <= ICACHE_LOOKUP;
                        end
                    end
                end

                // The fetch stage consumes this response in one cycle. If an
                // older redirect wins simultaneously, pipeline_control flushes
                // it and the cache simply returns to normal lookup.
                ICACHE_FAULT_RESPONSE: state <= ICACHE_LOOKUP;

                default: state <= ICACHE_LOOKUP;
            endcase
        end
    end

endmodule
